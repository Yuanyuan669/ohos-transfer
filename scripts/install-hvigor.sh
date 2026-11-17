#!/usr/bin/env bash
# Install the hvigor version that matches an OpenHarmony API 10 / 4.0 board.
#
# registry.npmjs.org and https://ohpm.openharmony.cn/ohpm/ both return 404 for
# @ohos/hvigor. The only working public registry found is HarmonyOS's npm mirror,
# and it still serves the legacy 3.x line:
#   @ohos/hvigor               -> 3.0.2 3.0.9 3.2.4
#   @ohos/hvigor-ohos-plugin   -> 3.0.2 3.0.9 3.2.4
# 3.2.4 is what DevEco 4.0 shipped, so it pairs with compileSdkVersion 10 and
# accepts the numeric form in build-profile.json5.
#
#   bash scripts/install-hvigor.sh                # 3.2.4
#   bash scripts/install-hvigor.sh 6.26.20        # the DevEco 26 line instead
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

HV_VERSION="${1:-3.2.4}"
PREFIX="${HVIGOR_INSTALL_DIR:-$OHOS_TOOLS_ROOT/hvigor-$HV_VERSION}"

step "选择 node"
NODE="$(resolve_node || true)"
[ -n "$NODE" ] || fail "找不到 node。装 DevEco Studio（自带 tools/node）或单独装 Node 18+。"
ok "$NODE  ($("$NODE" -v 2>/dev/null))"

step "npm install @ohos/hvigor@$HV_VERSION 到 $PREFIX"
mkdir -p "$PREFIX"
cd "$PREFIX"
[ -f package.json ] || "$NODE" "$(dirname "$NODE")/node_modules/npm/bin/npm-cli.js" init -y >/dev/null 2>&1
"$NODE" "$(dirname "$NODE")/node_modules/npm/bin/npm-cli.js" install \
  --registry "$OHOS_NPM_REGISTRY" \
  "@ohos/hvigor@$HV_VERSION" "@ohos/hvigor-ohos-plugin@$HV_VERSION" \
  || fail "npm 安装失败。检查 $OHOS_NPM_REGISTRY 是否可达；换版本：bash scripts/install-hvigor.sh <version>"

step "验证 CLI"
CLI="$PREFIX/node_modules/@ohos/hvigor/bin/hvigor-simple.js"
[ -f "$CLI" ] || fail "装完了但没找到 $CLI"
"$NODE" "$CLI" --version 2>&1 | tail -2

echo
ok "hvigor $HV_VERSION 就绪"
cat <<EOF

让脚本用它（env.sh 已默认指向 hvigor-3.2.4，若装了别的版本请覆盖）：
  export HVIGOR_CLI="$PREFIX/node_modules/@ohos/hvigor/bin/hvigor-simple.js"
  export NODE_PATH="$PREFIX/node_modules"
下一步：
  bash scripts/build.sh
EOF
