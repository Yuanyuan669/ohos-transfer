#!/usr/bin/env bash
# One command for the whole chain: report -> build -> sign -> deploy -> verify.
#   bash scripts/pipeline.sh
#   OHOS_TARGET=192.168.1.23:5555 bash scripts/pipeline.sh
#
# doctor.sh is advisory here: an absent board must not block producing a signed
# HAP, because the build host and the board are usually different machines.
# The hard device check happens in deploy.sh, where it belongs.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

step "环境体检（不通过也继续出包，只有部署需要设备）"
bash "$SCRIPT_DIR/doctor.sh" || warn "doctor 有待补项，见上"

step "补齐签名材料（如果没有）"
if [ ! -f "$OHOS_SIGN_DIR/homekiosk-profile.p7b" ]; then
  bash "$SCRIPT_DIR/make-signing-material.sh" || exit 1
else
  ok "signing/ 已有材料"
fi

bash "$SCRIPT_DIR/build.sh" "${1:-}" || exit 1
if [ -f "$OHOS_UNSIGNED_HAP" ]; then
  bash "$SCRIPT_DIR/sign.sh" || exit 1
fi

bash "$SCRIPT_DIR/deploy.sh" || exit 1
ok "pipeline 全绿：产物在 $OHOS_OUT_DIR"
