#!/usr/bin/env python3
"""独立核对 C 数据面的 WireGuard 握手与传输实现（不依赖被测代码）。

原理：test_main（C）在**可复现临时密钥**下产出一份握手/传输转录（transcript），
本脚本用**独立实现**（Python hashlib.blake2s + OpenSSL 提供的 X25519/ChaCha20-Poly1305）
按 WireGuard 协议（Noise_IKpsk2）重新推导并校验：

  - initiation 里静态公钥 / 时间戳的 AEAD 解密与哈希链
  - response 里空负载 AEAD 与哈希链（**这一条能抓到 KDF1/KDF2 误用**）
  - mac1（keyed BLAKE2s-128）计算
  - 双方会话密钥的传输消息加解密（含 counter 派生的 nonce）

脚本自带 RFC/官方向量自检（BLAKE2s、HMAC-BLAKE2s KDF、ChaCha20-Poly1305、X25519），
自检通过才说明脚本所用原语可信，从而握手核对结果可信。

依赖：cryptography（通过 `uv run --with cryptography python verify_handshake.py ...`）。
"""

import hashlib
import hmac
import sys

from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey,
    X25519PublicKey,
)
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

CONSTRUCTION = b"Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"
IDENTIFIER = b"WireGuard v1 zx2c4 Jason@zx2c4.com"
LABEL_MAC1 = b"mac1----"
ZERO_NONCE = b"\x00" * 12


def H(*parts: bytes) -> bytes:
    h = hashlib.blake2s()
    for p in parts:
        h.update(p)
    return h.digest()


def HMAC(key: bytes, data: bytes) -> bytes:
    return hmac.new(key, data, hashlib.blake2s).digest()


def KDF1(key: bytes, inp: bytes) -> bytes:
    return HMAC(HMAC(key, inp), b"\x01")


def KDF2(key: bytes, inp: bytes):
    prk = HMAC(key, inp)
    t0 = HMAC(prk, b"\x01")
    t1 = HMAC(prk, t0 + b"\x02")
    return t0, t1


def KDF3(key: bytes, inp: bytes):
    prk = HMAC(key, inp)
    t0 = HMAC(prk, b"\x01")
    t1 = HMAC(prk, t0 + b"\x02")
    t2 = HMAC(prk, t1 + b"\x03")
    return t0, t1, t2


def x25519(priv: bytes, pub: bytes) -> bytes:
    return X25519PrivateKey.from_private_bytes(priv).exchange(X25519PublicKey.from_public_bytes(pub))


def x25519_pub(priv: bytes) -> bytes:
    return X25519PrivateKey.from_private_bytes(priv).public_key().public_bytes_raw()


def aead_enc(key: bytes, nonce: bytes, pt: bytes, aad: bytes) -> bytes:
    return ChaCha20Poly1305(key).encrypt(nonce, pt, aad)


def aead_dec(key: bytes, nonce: bytes, ct: bytes, aad: bytes) -> bytes:
    return ChaCha20Poly1305(key).decrypt(nonce, ct, aad)


def mac1(static_pub: bytes, msg: bytes) -> bytes:
    key = H(LABEL_MAC1, static_pub)
    return hashlib.blake2s(msg, key=key, digest_size=16).digest()


FAILS = []


def check(cond: bool, msg: str) -> None:
    if cond:
        print(f"  [ok]   {msg}")
    else:
        print(f"  [FAIL] {msg}")
        FAILS.append(msg)


# ---------------------------------------------------------------- 原语自检
def selftest_primitives() -> None:
    print("-- Python 参考实现自检（RFC/官方向量）--")
    check(
        hashlib.blake2s(b"abc").hexdigest()
        == "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982",
        "BLAKE2s RFC 7693 'abc'",
    )
    # wireguard-go device/kdf_test.go：key="test-key", input="test-input"
    prk = HMAC(b"test-key", b"test-input")
    t0 = HMAC(prk, b"\x01")
    t1 = HMAC(prk, t0 + b"\x02")
    t2 = HMAC(prk, t1 + b"\x03")
    check(prk.hex() == "ed378e02e152b574e0d9e01fb029a7066c3cc687917c28bf9dfe5b042769fa46", "HMAC-BLAKE2s prk")
    check(t0.hex() == "6f0e5ad38daba1bea8a0d213688736f19763239305e0f58aba697f9ffc41c633", "KDF t0")
    check(t1.hex() == "df1194df20802a4fe594cde27e92991c8cae66c366e8106aaa937a55fa371e8a", "KDF t1")
    check(t2.hex() == "fac6e2745a325f5dc5d11a5b165aad08b0ada28e7b4e666b7c077934a4d76c24", "KDF t2")

    # RFC 8439 §2.8.2 AEAD
    key = bytes(range(0x80, 0xA0))
    aad = bytes.fromhex("50515253c0c1c2c3c4c5c6c7")
    nonce = bytes.fromhex("070000004041424344454647")
    pt = bytes.fromhex(
        "4c616469657320616e642047656e746c656d656e206f662074686520636c617373206f6620"
        "2739393a204966204920636f756c64206f6666657220796f75206f6e6c79206f6e65207469"
        "7020666f7220746865206675747572652c2073756e73637265656e20776f756c6420626520"
        "69742e"
    )
    exp = bytes.fromhex(
        "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671"
        "282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091"
        "b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b59"
        "4f09e26a7e902ecbd0600691"
    )
    check(aead_enc(key, nonce, pt, aad) == exp, "ChaCha20-Poly1305 RFC 8439 §2.8.2")

    # RFC 7748 §5.2 / §6.1
    got = x25519(
        bytes.fromhex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
        bytes.fromhex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"),
    )
    check(got.hex() == "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552", "X25519 RFC 7748 §5.2 #1")
    a_priv = bytes.fromhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
    b_priv = bytes.fromhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
    check(
        x25519(a_priv, x25519_pub(b_priv)).hex()
        == "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742",
        "X25519 RFC 7748 §6.1 DH",
    )


# ---------------------------------------------------------------- 转录核对
def parse(path: str) -> dict:
    d = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or "=" not in line:
                continue
            k, v = line.split("=", 1)
            d[k] = bytes.fromhex(v)
    return d


def verify(path: str) -> None:
    t = parse(path)
    print(f"-- 核对转录 {path} --")
    a_priv = t["a_priv"]
    a_pub = t["a_pub"]
    b_priv = t["b_priv"]
    b_pub = t["b_pub"]
    use_psk = t["use_psk"] == b"\x01"
    psk = t["psk"] if use_psk else b"\x00" * 32
    eph_i = t["eph_i"]
    eph_r = t["eph_r"]
    msg1 = t["msg1"]
    msg2 = t["msg2"]

    check(t["a_pub"] == x25519_pub(a_priv), "a_pub 由 a_priv 派生一致")
    check(t["b_pub"] == x25519_pub(b_priv), "b_pub 由 b_priv 派生一致")
    check(msg1[:4] == b"\x01\x00\x00\x00", "initiation type=1")
    check(len(msg1) == 148, "initiation 长度 148")
    check(msg2[:4] == b"\x02\x00\x00\x00", "response type=2")
    check(len(msg2) == 92, "response 长度 92")
    check(msg2[12:44] == x25519_pub(eph_r), "response 临时公钥 = eph_r 派生")

    # ---- initiation：以 B（响应方）视角处理 ----
    ck = H(CONSTRUCTION)
    h = H(H(ck, IDENTIFIER), b_pub)
    sender_i = msg1[4:8]
    eph_i_pub = msg1[8:40]
    check(eph_i_pub == x25519_pub(eph_i), "initiation 临时公钥 = eph_i 派生")
    ck = KDF1(ck, eph_i_pub)
    h = H(h, eph_i_pub)
    ck, k = KDF2(ck, x25519(b_priv, eph_i_pub))
    static_i = aead_dec(k, ZERO_NONCE, msg1[40:88], h)
    check(static_i == a_pub, "initiation 静态公钥解密 = A 公钥")
    h = H(h, msg1[40:88])
    ck, k = KDF2(ck, x25519(b_priv, static_i))
    ts = aead_dec(k, ZERO_NONCE, msg1[88:116], h)
    check(len(ts) == 12, "initiation 时间戳解密（12 字节 TAI64N）")
    h = H(h, msg1[88:116])
    check(mac1(b_pub, msg1[:116]) == msg1[116:132], "initiation mac1 正确")
    check(msg1[132:148] == b"\x00" * 16, "initiation mac2 为零（v1 无 cookie）")

    # ---- response（用 eph_r 独立推导）----
    check(msg2[8:12] == sender_i, "response receiver index 回指 initiation sender")
    eph_r_pub = msg2[12:44]
    ck = KDF1(ck, eph_r_pub)
    h = H(h, eph_r_pub)
    ck = KDF1(ck, x25519(eph_r, eph_i_pub))  # ee：响应方临时 × 发起方临时
    ck = KDF1(ck, x25519(eph_r, static_i))   # se：响应方临时 × 发起方静态
    ck, tau, k = KDF3(ck, psk)
    h = H(h, tau)
    pt = aead_dec(k, ZERO_NONCE, msg2[44:60], h)
    check(pt == b"", "response 空负载 AEAD 解密成功（KDF 顺序正确）")
    h = H(h, msg2[44:60])
    check(mac1(a_pub, msg2[:60]) == msg2[60:76], "response mac1 正确")

    # ---- 传输密钥与消息 ----
    send_i, recv_i = KDF2(ck, b"")
    recv_r, send_r = send_i, recv_i

    def dec_transport(key: bytes, msg: bytes) -> bytes:
        counter = int.from_bytes(msg[8:16], "little")
        nonce = b"\x00" * 4 + counter.to_bytes(8, "little")
        return aead_dec(key, nonce, msg[16:], b"")

    ab = t["transport_ab"]
    check(ab[:4] == b"\x04\x00\x00\x00", "transport_ab type=4")
    check(dec_transport(send_i, ab) == t["plain_ab"], "A→B transport 用派生密钥解密一致")
    ba = t["transport_ba"]
    check(dec_transport(send_r, ba) == t["plain_ba"], "B→A transport 用派生密钥解密一致")
    # A→B 的 receiver = B 的 sender index（response 里的 sender）；B→A 反之
    check(ab[4:8] == msg2[4:8], "A→B transport receiver = B 的 sender index")
    check(ba[4:8] == msg1[4:8], "B→A transport receiver = A 的 sender index")


def main() -> int:
    selftest_primitives()
    if FAILS:
        print("参考实现自检失败，握手核对结果不可信")
        return 2
    paths = sys.argv[1:]
    if not paths:
        paths = ["hosttest_transcript.txt"]
    for p in paths:
        # 每次核对前重置失败列表：分文件报告
        before = len(FAILS)
        verify(p)
        if len(FAILS) > before:
            print(f"转录 {p} 核对失败")
    print("=== 独立核对结果：%s（失败 %d 项）===" % ("PASS" if not FAILS else "FAIL", len(FAILS)))
    return 0 if not FAILS else 1


if __name__ == "__main__":
    sys.exit(main())
