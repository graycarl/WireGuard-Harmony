/*
 * WireGuard 协议核心公共定义（决策 0001/0002：数据面+握手全在 C 层）。
 *
 * 分层：
 *   wg_device.c    设备/Peer/会话/allowed-ips/发送队列（状态管理，全部在锁内操作）
 *   wg_handshake.c Noise IK 握手（initiation/response 生成与消费）
 *   wg_transport.c type 4 传输消息加解密、重放窗口、cryptokey routing、roaming
 *   wg_runtime.c   tun↔UDP 转发线程 + 维护定时器线程
 *   napi_init.cpp  NAPI 薄胶水（契约 docs/dev-contracts.md §8）
 *
 * 定时器常量对齐 wireguard 白皮书 / kernel / wireguard-go 实现。
 */
#ifndef WIREGUARD_H
#define WIREGUARD_H
#ifdef __cplusplus
extern "C" {
#endif

#include "wg_log.h"

#include <pthread.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <netinet/in.h>
#include <sys/socket.h>

/* ---- 协议常量 ---- */
#define WG_CONSTRUCTION "Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"
#define WG_IDENTIFIER "WireGuard v1 zx2c4 Jason@zx2c4.com"
#define WG_LABEL_MAC1 "mac1----"
#define WG_LABEL_COOKIE "cookie--"

#define WG_MSG_INITIATION 1
#define WG_MSG_RESPONSE 2
#define WG_MSG_COOKIE 3
#define WG_MSG_TRANSPORT 4

#define WG_INITIATION_LEN 148
#define WG_RESPONSE_LEN 92
#define WG_COOKIE_LEN 64
#define WG_TRANSPORT_HEADER 16
#define WG_AEAD_TAG 16

/* ---- 定时器/限制常量（对齐 wireguard 白皮书与 kernel 实现） ---- */
#define WG_REKEY_AFTER_TIME 120.0        /* 发起方会话满 120s 主动重协商 */
#define WG_REJECT_AFTER_TIME 180.0       /* 会话满 180s 作废 */
#define WG_REKEY_ATTEMPT_TIME 90.0       /* 握手最长尝试窗口 */
#define WG_REKEY_TIMEOUT 5.0             /* 握手重试间隔 */
#define WG_KEEPALIVE_TIMEOUT 10.0        /* 收包后 10s 无回包 → 回 keepalive */
#define WG_REKEY_AFTER_MESSAGES (1ULL << 60)
#define WG_REJECT_AFTER_MESSAGES (0xFFFFFFFFFFFFFFFFULL - (1ULL << 13) - 1ULL)
#define WG_TIMER_TICK_MS 250

#define WG_MAX_PEERS 8
#define WG_MAX_ALLOWED_IPS 64
#define WG_REPLAY_WINDOW_BYTES 256 /* 2048 bit */
#define WG_QUEUE_LEN 8
#define WG_QUEUE_SLOT 2048
#define WG_MAX_PACKET 2048 /* 内层 IP 包上限（MTU 1420 + 余量） */

#define WG_VERSION "wg-harmony 1.0.0"

typedef struct {
    uint8_t addr[16];
    uint8_t family; /* 4 / 6 */
    uint8_t cidr;
} wg_allowed_ip;

typedef struct {
    uint32_t index;      /* 本端 sender index（对端消息的 receiver index，用于收包查表） */
    uint32_t remote_index; /* 对端 sender index（我方发包时填 receiver 字段） */
    uint8_t send_key[32];
    uint8_t recv_key[32];
    uint64_t send_nonce;
    uint64_t recv_top;   /* 已见最大 counter */
    uint8_t recv_window[WG_REPLAY_WINDOW_BYTES];
    double born_mono;
    bool valid;
    bool initiating; /* 我方发起（承担 rekey 责任） */
} wg_keypair;

typedef struct {
    /* 配置 */
    uint8_t public_key[32];
    uint8_t preshared_key[32];
    bool has_psk;
    wg_allowed_ip allowed[WG_MAX_ALLOWED_IPS];
    int n_allowed;
    struct sockaddr_storage endpoint;
    socklen_t endpoint_len;
    bool has_endpoint;
    uint16_t persistent_keepalive;

    /* 握手状态（我方作为发起方） */
    bool handshake_pending;
    uint32_t pending_index;
    uint8_t pending_eph_priv[32];
    uint8_t pending_ck[32];
    uint8_t pending_hash[32];
    double first_attempt_mono;
    double last_attempt_mono;

    /* 握手状态（我方作为响应方的防重放） */
    uint8_t last_tai64n[12];
    bool has_tai64n;
    uint8_t last_initiation[WG_INITIATION_LEN];
    size_t last_initiation_len;
    uint8_t cached_response[WG_RESPONSE_LEN];
    size_t cached_response_len;
    bool has_cached_response;

    /* 会话：双槽轮换（cur + prev，收包按 index 全扫） */
    wg_keypair kp[2];
    int cur_kp; /* 0/1；-1 = 无 */

    /* 统计与保活 */
    uint64_t rx_bytes;
    uint64_t tx_bytes;
    uint64_t last_handshake_ms; /* epoch ms，0 = 从未 */
    double last_rx_mono;        /* 最近收到任何认证消息，0 = 从未 */
    double last_tx_mono;        /* 最近发出任何消息，0 = 从未 */
    bool want_session;          /* 有数据待发，需要会话 */
    bool need_keepalive;        /* 收包后久未发送，需回 keepalive */

    /* 握手未完成期间的发送队列（内层 IP 包） */
    uint8_t queue[WG_QUEUE_LEN][WG_QUEUE_SLOT];
    uint16_t queue_len[WG_QUEUE_LEN];
    int queue_count;
} wg_peer;

typedef struct {
    uint8_t private_key[32];
    uint8_t public_key[32];
    uint16_t listen_port;
    int tun_fd;
    int sock_fd;
    wg_peer peers[WG_MAX_PEERS];
    int n_peers;
    volatile bool running;
    bool threads_started;
    pthread_mutex_t lock;
    pthread_t th_tun;
    pthread_t th_udp;
    pthread_t th_timer;
    char last_error[160];
} wg_device;

/* ---- wg_device.c ---- */
void wg_device_init(wg_device *dev);
void wg_device_destroy(wg_device *dev);
/* 解析 configJson（结构见契约 §8），填 peers；返回 0 / -1 参数错 / -2 DNS 解析失败(last_error=主机名) */
int wg_device_configure(wg_device *dev, const char *config_json);
wg_peer *wg_peer_by_pubkey(wg_device *dev, const uint8_t pubkey[32]);
/* 出向：按目的 IP 最长前缀匹配选 peer（无匹配返回 NULL） */
wg_peer *wg_peer_for_packet(wg_device *dev, const uint8_t *pkt, size_t len);
/* 入向 cryptokey routing：源 IP 是否在该 peer allowedIPs 内 */
bool wg_peer_allows_source(const wg_peer *peer, const uint8_t *pkt, size_t len);
/* 装新会话（轮换双槽），记录握手时间 */
void wg_peer_install_keypair(wg_device *dev, wg_peer *peer, const wg_keypair *kp);
/* 队列：握手期间暂存内层包；满则丢最旧 */
void wg_peer_queue(wg_peer *peer, const uint8_t *pkt, size_t len);
uint32_t wg_new_index(wg_device *dev); /* 不冲突的随机 sender index */
bool wg_sockaddr_equal(const struct sockaddr_storage *a, const struct sockaddr_storage *b);
void wg_sockaddr_to_string(const struct sockaddr_storage *ss, char *out, size_t cap);
/* v4 端点 → v4-mapped v6（双栈 socket 发送用） */
void wg_sockaddr_to_v6mapped(const struct sockaddr_storage *in, struct sockaddr_storage *out);
void wg_set_last_error(wg_device *dev, const char *fmt, const char *arg);

/* ---- wg_handshake.c ---- */
/* 生成 initiation（写入 peer pending 状态），out 容量 >= WG_INITIATION_LEN。返回 false=无法（如无端点/随机失败） */
bool wg_handshake_create_initiation(wg_device *dev, wg_peer *peer, uint8_t *out, size_t *out_len);
/* 消费 initiation：out_response 容量 >= WG_RESPONSE_LEN；成功返回 true（含重复 initiation 重发缓存响应） */
bool wg_handshake_consume_initiation(wg_device *dev, const uint8_t *msg, size_t len,
                                     uint8_t *out_response, size_t *out_len, wg_peer **peer_out);
/* 消费 response：完成我方发起的握手，安装会话；成功返回对应 peer，失败 NULL */
wg_peer *wg_handshake_consume_response(wg_device *dev, const uint8_t *msg, size_t len);

/* ---- wg_transport.c ---- */
/* 加密内层包为 transport 消息。返回消息长度；0=无有效会话（调用方应入队并触发握手）；<0=丢弃 */
int wg_transport_encrypt(wg_device *dev, wg_peer *peer, const uint8_t *pkt, size_t len,
                         uint8_t *out, size_t out_cap);
/* 解密 transport 消息：校验重放窗口与 cryptokey routing；处理 roaming（src 为报文来源地址）。
 * plain_out 长度于 *plain_len（0 = keepalive，不写 tun）。命中 peer 于 *peer_out。 */
bool wg_transport_decrypt(wg_device *dev, const uint8_t *msg, size_t len,
                          const struct sockaddr_storage *src,
                          uint8_t *plain_out, size_t *plain_len, wg_peer **peer_out);
/* 发送空 keepalive（调用方持锁）。返回 false=无会话 */
bool wg_transport_make_keepalive(wg_device *dev, wg_peer *peer, uint8_t *out, size_t *out_len);

/* ---- wg_runtime.c ---- */
int wg_runtime_start(wg_device *dev); /* 0 成功 / -4 线程创建失败 */
void wg_runtime_stop(wg_device *dev);

/* ---- KAT（wg_kat.c）：启动自检，false=失败 ---- */
bool wg_kat_selftest(void);

/* 全局单例（数据面单实例，决策 0006 §4） */
extern wg_device g_wg;

#ifdef __cplusplus
}
#endif
#endif /* WIREGUARD_H */
