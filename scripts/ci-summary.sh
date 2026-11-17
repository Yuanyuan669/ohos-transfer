#!/usr/bin/env bash
# One-paragraph CI log summary: what was built, signed with what, and whether the
# board accepted it. Safe to run any time; never fails the pipeline on its own.
#   bash scripts/ci-summary.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "== HomeKiosk CI summary ($(date -u +%FT%TZ)) =="
echo "  bundle      : $OHOS_BUNDLE / $OHOS_MODULE / product=$OHOS_PRODUCT mode=$OHOS_BUILD_MODE"
echo "  host        : $(uname -srm 2>/dev/null || echo unknown)  java=$("$JAVA_BIN" -version 2>&1 | head -1 | tr -d '"')  node=$(resolve_node 2>/dev/null || echo none)"

API=$(sed -n 's/.*"apiVersion": *"\([0-9]*\)".*/\1/p' "$OHOS_SDK_TOOLCHAINS/oh-uni-package.json" 2>/dev/null | head -1)
echo "  sdk         : ${OHOS_BASE_SDK_HOME:-unset}  api=${API:-?}"

if [ -f "$OHOS_UNSIGNED_HAP" ]; then
  echo "  unsigned    : $OHOS_UNSIGNED_HAP ($(wc -c < "$OHOS_UNSIGNED_HAP") bytes)"
else
  echo "  unsigned    : 无（build.sh 未产出）"
fi

if [ -f "$OHOS_SIGNED_HAP" ]; then
  echo "  signed      : $OHOS_SIGNED_HAP ($(wc -c < "$OHOS_SIGNED_HAP") bytes)"
  if [ -f "$OHOS_SIGN_DIR/homekiosk-profile.p7b" ]; then
    PB=$(grep -a -oE '"bundle-name" *: *"[^"]+"' "$OHOS_SIGN_DIR/homekiosk-profile.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    echo "  profile     : bundle-name=$PB  alias=$OHOS_KEY_ALIAS  keystore=$(basename "$OHOS_SIGN_DIR/homekiosk.p12" 2>/dev/null)"
  fi
else
  echo "  signed      : 无（sign.sh 未产出）"
fi

HDC_BIN="$(resolve_hdc || true)"
if [ -n "$HDC_BIN" ]; then
  echo "  hdc         : $("$HDC_BIN" -v 2>/dev/null | head -1)  ($HDC_BIN)"
  DEV="$(list_targets)"
  if [ -n "$DEV" ]; then
    echo "  device      : $(echo "$DEV" | head -1)"
    export OHOS_TARGET="$(echo "$DEV" | head -1 | awk '{print $1}')"
    echo "  device api  : $(hdc_run shell getparam const.product.software.version 2>/dev/null | tr -d '\r')"
    echo "  app on dev  : $(hdc_run shell bm dump -n "$OHOS_BUNDLE" 2>/dev/null | tr -d '\r' | grep -oE '"versionName": *"[^"]*"' | head -1 || echo 未安装)"
    [ -f "$OHOS_SHOT" ] && echo "  proof       : $OHOS_SHOT ($(wc -c < "$OHOS_SHOT") bytes)"
  else
    echo "  device      : 无在线设备（这一步只出包，装机需要 runner 能到达板子）"
  fi
else
  echo "  hdc         : 未找到"
fi
