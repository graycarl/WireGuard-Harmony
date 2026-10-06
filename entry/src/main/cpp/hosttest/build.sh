#!/usr/bin/env bash
# 主机侧协议仿真测试：编译（ASan/UBSan）→ 运行 C 断言 → 独立 Python 协议核对。
#
# 用法：  ./build.sh
# 依赖：  macOS/Linux 自带 cc；可选 uv（用于独立 Python 核对，缺失则跳过并提示）
set -euo pipefail
cd "$(dirname "$0")"

CC=${CC:-cc}
CFLAGS=${CFLAGS:--std=c11 -Wall -Wextra -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer}

SRCS=(
  ../blake2s.c
  ../chacha20poly1305.c
  ../curve25519.c
  ../wg_base64.c
  ../wg_device.c
  ../wg_handshake.c
  ../wg_json.c
  ../wg_kat.c
  ../wg_log.c
  ../wg_runtime.c
  ../wg_transport.c
  test_main.c
)

echo "== compile hosttest with ${CC} =="
# shellcheck disable=SC2086
"${CC}" ${CFLAGS} -o wg_hosttest "${SRCS[@]}"

echo "== run C assertions =="
./wg_hosttest transcript_nopsk.txt transcript_psk.txt

echo
echo "== independent python protocol check =="
if command -v uv >/dev/null 2>&1; then
  uv run --quiet --with cryptography python verify_handshake.py transcript_nopsk.txt transcript_psk.txt
else
  echo "[skip] uv not found; skipping independent protocol check (C assertions above still ran)"
fi

echo
echo "== hosttest PASS =="
