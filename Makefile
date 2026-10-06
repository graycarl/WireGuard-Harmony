# WireGuard 命令行构建封装（agent / 开发者使用）
# 底层调用 DevEco Studio 内置工具链（hvigor + JBR），无需打开 IDE
#
# 若本机 DevEco Studio 不在 /Applications/DevEco-Studio.app，改下面三个路径即可

DEVECO_APP := /Applications/DevEco-Studio.app
DEVECO_SDK := $(DEVECO_APP)/Contents/sdk
JBR_HOME   := $(DEVECO_APP)/Contents/jbr/Contents/Home
HVIGOR_BIN := $(DEVECO_APP)/Contents/tools/hvigor/bin
OHPM_BIN   := $(DEVECO_APP)/Contents/tools/ohpm/bin
HVIGOR     := $(HVIGOR_BIN)/hvigorw   # 绝对路径：make 对简单命令跳过 shell 直接 exec，用不到导出后的 PATH
NODE       := $(or $(shell command -v node 2>/dev/null),$(DEVECO_APP)/Contents/tools/node/bin/node)

export DEVECO_SDK_HOME := $(DEVECO_SDK)
export JAVA_HOME := $(JBR_HOME)
export PATH := $(OHPM_BIN):$(HVIGOR_BIN):$(PATH)

HVIGOR_FLAGS := --mode module -p product=default -p buildMode=debug --no-daemon

.PHONY: build test ohpm-install sign-import sign-status clean commit help

build: ## 编译 + 打包 debug HAP（产物在 entry/build/default/outputs/；配好签名则含 *-signed.hap）
	$(HVIGOR) assembleHap $(HVIGOR_FLAGS)

ohpm-install: ## 拉取 ohpm 依赖（首次 make test 前必需；无网时跳过）
	ohpm install --all

# 签名材料：build-profile.json5 入库时 signingConfigs 恒为 []，材料放本机 signing-config.local.json，
# 由 hvigorfile.ts 经 config.ohos.overrides.signingConfig 注入（详见脚本内注释）。
sign-import: ## 把 DevEco Studio 写进 build-profile.json5 的签名材料搬到本机文件并还原之
	$(NODE) scripts/sign-config.mjs import

sign-status: ## 查看当前签名材料来源（仓库是否干净 / 材料文件是否存在）
	$(NODE) scripts/sign-config.mjs status

# ⚠️ hypium 用例失败时 hvigor 仍可能打印 BUILD SUCCESSFUL（假绿），
#    所以这里既看退出码、也 grep "Error in "，两者任一命中即判失败。
test: ## 跑 LocalUnit 单测（hypium，entry/src/test；自动处理缺 oh_modules）
	@if [ ! -d oh_modules ]; then echo "[make test] 缺少 oh_modules → 自动执行 ohpm install --all"; ohpm install --all; fi
	@set -e; log=$$(mktemp); \
	if ! $(HVIGOR) test $(HVIGOR_FLAGS) > $$log 2>&1; then tail -30 $$log; echo "❌ hvigor 执行失败"; exit 1; fi; \
	tail -12 $$log; \
	if grep -q "Error in " $$log; then echo "❌ 有用例失败（注意：hvigor 仍会报 BUILD SUCCESSFUL）"; grep -m20 "Error in " $$log; exit 1; fi; \
	echo "✅ 单测通过（未发现失败用例）"

clean: ## 清理构建产物
	rm -rf entry/build

commit: ## git 提交全部改动（用法：make commit MSG="提交信息"）
	@test -n "$(MSG)" || (echo '用法：make commit MSG="提交信息"'; exit 1)
	git add -A && git commit -m "$(MSG)"

help: ## 列出可用目标
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'
