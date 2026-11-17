#!/usr/bin/env bash
# Sign the HAP with hap-sign-tool: no IDE, no network, just JDK.
#   bash scripts/sign.sh
#
# Expected materials (scripts/make-signing-material.sh creates all of them):
#   signing/homekiosk.p12        app key pair, alias homekiosk-app-key-v1
#   signing/homekiosk-app.cer    3-cert chain ending in that key's certificate
#   signing/homekiosk-profile.p7b profile whose bundle-name == $OHOS_BUNDLE
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [ -f "$OHOS_SIGNED_HAP" ] && [ ! -f "$OHOS_UNSIGNED_HAP" ]; then
  step "已存在签名包"; ok "$OHOS_SIGNED_HAP"; exit 0
fi
[ -f "$OHOS_UNSIGNED_HAP" ] || fail "找不到 $OHOS_UNSIGNED_HAP，先跑 build.sh"

step "定位签名工具"
JAR="$(resolve_sign_jar || true)"
[ -n "$JAR" ] || fail "hap-sign-tool.jar 未找到。export OHOS_SDK_HOME=<SDK>/openharmony 或 HAP_SIGN_JAR=<SDK>/toolchains/lib/hap-sign-tool.jar"
ok "$JAR"
"$JAVA_BIN" -version >/dev/null 2>&1 || fail "需要可执行的 JDK：$JAVA_BIN 跑不起来（env.sh 会用 JAVA_HOME 定位）"
ok "java: $("$JAVA_BIN" -version 2>&1 | head -1)"

step "定位签名材料"
# Ordered patterns: the generic *.cer / *.p12 globs would otherwise pick up the
# exported CA certificates or the SDK's own test keystore.
pick() {
  local override="$1"; shift
  [ -n "$override" ] && { [ -f "$override" ] && { echo "$override"; return 0; }; return 1; }
  local pat f
  for pat in "$@"; do
    for f in $OHOS_SIGN_DIR/$pat; do [ -f "$f" ] && { echo "$f"; return 0; }; done
  done
  return 1
}
KS="$(pick "${OHOS_KEYSTORE:-}" 'homekiosk.p12' 'app-*.p12' '*.p12' || true)"
CRT="$(pick "${OHOS_APP_CERT:-}" 'homekiosk-app.cer' '*-app.cer' '*.cer' || true)"
PF="$(pick "${OHOS_PROFILE:-}" 'homekiosk-profile.p7b' '*-profile.p7b' '*.p7b' || true)"
[ -n "$KS" ]  || fail "缺 .p12 密钥库。跑 bash scripts/make-signing-material.sh 生成"
[ -n "$CRT" ] || fail "缺 .cer 证书链。同上"
[ -n "$PF" ]  || fail "缺 .p7b Profile（bundleName 必须等于 $OHOS_BUNDLE，否则装上就报 9568322/9568313）"
[ "$(basename "$KS")" = "OpenHarmony.p12" ] && warn "正在用 SDK 自带的 OpenHarmony.p12 签名，别名要对得上；正常应该用 signing/homekiosk.p12"
ok "keystore=$KS"; ok "cert=$CRT"; ok "profile=$PF"

step "sign-app"
rm -f "$OHOS_SIGNED_HAP"
"$JAVA_BIN" -jar "$JAR" sign-app \
  -mode localSign \
  -signAlg SHA256withECDSA \
  -keystoreFile "$KS" \
  -keystorePwd "$OHOS_STORE_PWD" \
  -keyAlias "$OHOS_KEY_ALIAS" \
  -keyPwd "$OHOS_KEY_PWD" \
  -appCertFile "$CRT" \
  -profileFile "$PF" \
  -inFile "$OHOS_UNSIGNED_HAP" \
  -outFile "$OHOS_SIGNED_HAP" \
  || fail "签名失败。常见三种：\n     'Signature did not verify' -> .cer 的叶子证书和 -keyAlias 的密钥不是同一对\n     'certificate in profile' 后报错 -> Profile 里 distribution-certificate 与 -appCertFile 不一致\n     'profile 解析错' -> .p7b 与本 SDK 不成套，重跑 make-signing-material.sh"
[ -s "$OHOS_SIGNED_HAP" ] || fail "签名后包体为空"
ok "signed -> $OHOS_SIGNED_HAP ($(wc -c < "$OHOS_SIGNED_HAP") bytes)"

step "verify-app 自检"
"$JAVA_BIN" -jar "$JAR" verify-app -inFile "$OHOS_SIGNED_HAP" \
  -outCertChain "$OHOS_OUT_DIR/verify-chain.cer" -outProfile "$OHOS_OUT_DIR/verify-profile.p7b" \
  | grep -E 'verify: |Digest verify|Signature Algorithm' | sed 's/^.*INFO  - /    /'
rm -f "$OHOS_OUT_DIR/verify-chain.cer" "$OHOS_OUT_DIR/verify-profile.p7b"
