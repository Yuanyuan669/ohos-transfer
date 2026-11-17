#!/usr/bin/env bash
# Build the HAP with hvigor. Produces build-artifacts/entry-unsigned.hap
# (hvigor skips signing because build-profile.json5 has no signingConfigs).
#   bash scripts/build.sh [--release]
#
# Two entry points, tried in this order:
#   A) scripts/../hvigorw          - what DevEco generates for your exact IDE version
#   B) node hvigor-simple.js       - era-matching hvigor installed by
#                                    scripts/install-hvigor.sh, no IDE needed
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

MODE="$OHOS_BUILD_MODE"
[ "${1:-}" = "--release" ] && MODE="release"

step "检查构建前置条件"
[ -d "$OHOS_BASE_SDK_HOME/openharmony/toolchains" ] || {
  [ -n "${OHOS_SDK_HOME:-}" ] || fail "OpenHarmony SDK 未就位（$OHOS_BASE_SDK_HOME/openharmony 不存在）。跑 bash scripts/get-ohos-sdk.sh"
}
ok "SDK base: $OHOS_BASE_SDK_HOME"
[ -f "$OHOS_SDK_TOOLCHAINS/hdc.exe" ] || warn "toolchains 里没找到 hdc.exe，稍后部署会失败"

HV=()
if [ -n "${HVIGORW:-}" ]; then
  HV=("$HVIGORW")
elif [ -x ./hvigorw ]; then
  HV=("./hvigorw")
elif [ -f ./hvigorw.bat ]; then
  HV=(cmd //c hvigorw.bat)
elif [ -f ./hvigorw ]; then
  HV=(sh ./hvigorw)
elif [ -f "$HVIGOR_CLI" ] && [ -d "$NODE_PATH" ] && NODE="$(resolve_node || true)" && [ -n "$NODE" ]; then
  HV=("$NODE" "$HVIGOR_CLI")
else
  fail "既没有 ./hvigorw，也没有 hvigor CLI（$HVIGOR_CLI）。\n     跑一次:  bash scripts/install-hvigor.sh"
fi
ok "hvigor -> ${HV[*]}"

step "assembleHap (mode=$MODE)"
mkdir -p "$OHOS_OUT_DIR"
"${HV[@]}" assembleHap --mode module \
  -p "product=$OHOS_PRODUCT" \
  -p "buildMode=$MODE" \
  --no-daemon || fail "hvigor 构建失败。按出现顺序排查：\n     1) 'Unable to find sdk.dir / OHOS_BASE_SDK_HOME' -> export OHOS_BASE_SDK_HOME=D:/ohos-tools/sdk\n     2) 'Unable to find the following components: toolchains:10' -> \$OHOS_BASE_SDK_HOME 下要有以 API 号命名的目录（10/）\n     3) 'spawn java ENOENT' -> JDK 不在 PATH；env.sh 会用 JAVA_HOME 补\n     4) ArkTS 编译错 -> 是真代码问题，错误里带文件名和行号"

step "收集产物"
HAP=$(find "$PROJ_ROOT/$OHOS_MODULE/build" -name '*.hap' -not -path '*/node_modules/*' 2>/dev/null | sort | tail -1)
[ -n "$HAP" ] || fail "没找到 .hap 产物（$OHOS_MODULE/build 下）。检查上面的 hvigor 输出。"
ok "产物: $HAP ($(wc -c < "$HAP") bytes)"
case "$(basename "$HAP")" in
  *unsigned*)
    cp "$HAP" "$OHOS_UNSIGNED_HAP"; ok "未签名 -> $OHOS_UNSIGNED_HAP，下一步跑 sign.sh" ;;
  *)
    cp "$HAP" "$OHOS_SIGNED_HAP"; ok "已带签名 -> $OHOS_SIGNED_HAP（sign.sh 会跳过）" ;;
esac
ls -l "$OHOS_OUT_DIR"
