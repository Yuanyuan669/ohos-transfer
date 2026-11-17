#!/usr/bin/env bash
# Build a complete, self-consistent signing set for a stock OpenHarmony board:
#
#   OpenHarmony Application Root CA      (public test PKI shipped inside the SDK)
#     └── OpenHarmony Application CA     (private key is in OpenHarmony.p12)
#           └── HomeKiosk App            (issued here, valid 10 years)
#
# The OpenHarmony SDK ships OpenHarmony.p12 together with the *private keys* of
# that root and sub-CA, so an app can be certified by the chain a developer
# image already trusts -- no vendor-issued certificate, no AppGallery account.
# Verified working with hap-sign-tool 4.0.10.13 on 2026-11-14.
#
# Outputs, all under signing/ (git-ignored; on CI regenerate or restore from
# secrets instead):
#   root-ca.cer / app-ca.cer     the two public CA certificates
#   homekiosk.p12                our app key pair (alias homekiosk-app-key-v1)
#   homekiosk-app.cer            3-cert chain: leaf, sub-CA, root
#   homekiosk-profile.json       profile carrying our bundle name, unsigned
#   homekiosk-profile.p7b        that profile, signed by the Profile Release key
#
# Re-running is safe: everything is recreated from scratch.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

LIB="${OHOS_SDK_TOOLCHAINS%/}/lib"
SIGN="$PROJ_ROOT/signing"
JAR="$LIB/hap-sign-tool.jar"
SDK_P12="$LIB/OpenHarmony.p12"
SDK_PEM="$LIB/OpenHarmonyProfileRelease.pem"
SDK_PROF="$LIB/UnsgnedReleasedProfileTemplate.json"

BUNDLE="${OHOS_BUNDLE:-com.local.homekiosk}"
APP_ALIAS="${OHOS_KEY_ALIAS:-homekiosk-app-key-v1}"
APP_PWD="${OHOS_KEY_PWD:-123456}"
STORE_PWD="${OHOS_STORE_PWD:-123456}"
CA_ALIAS="openharmony application ca"
PROFILE_ALIAS="openharmony application profile release"
P12_PWD="${OHOS_SDK_P12_PWD:-123456}"

for f in "$JAR" "$SDK_P12" "$SDK_PEM" "$SDK_PROF"; do
  [ -f "$f" ] || fail "缺少 $f\n     先跑 bash scripts/get-ohos-sdk.sh，或 export OHOS_SDK_TOOLCHAINS=<SDK>/toolchains"
done
need "$JAVA_BIN" || fail "需要 JDK：$JAVA_BIN 不可执行"

sig() {
  "$JAVA_BIN" -jar "$JAR" "$@" 2>&1 |
    grep -vE '^[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} (DEBUG|TRACE)' |
    sed 's/^11-.*INFO  - /    /'
}

mkdir -p "$SIGN"
cd "$SIGN"

step "1/5 导出 OpenHarmony 的两级 CA 证书"
# OpenHarmonyProfileRelease.pem = root CA, application CA, profile cert (in that order)
awk 'BEGIN{n=0} /BEGIN CERT/{n++} n>0{print > (".c" n ".pem")}' "$SDK_PEM"
mv .c1.pem root-ca.cer
mv .c2.pem app-ca.cer
rm -f .c3.pem
openssl x509 -in root-ca.cer -noout -subject | sed 's/^/    /'
openssl x509 -in app-ca.cer -noout -subject | sed 's/^/    /'

step "2/5 生成应用密钥对 -> homekiosk.p12"
rm -f homekiosk.p12
sig generate-keypair -keyAlias "$APP_ALIAS" -keyPwd "$APP_PWD" \
  -keyAlg ECC -keySize NIST-P-256 \
  -keystoreFile homekiosk.p12 -keystorePwd "$STORE_PWD" \
  | grep -iE 'success|fail|error' || true

step "3/5 让 Application CA 给应用证书签名（10 年）"
rm -f homekiosk-app.cer
sig generate-app-cert -keyAlias "$APP_ALIAS" -keyPwd "$APP_PWD" \
  -issuer "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA" \
  -issuerKeyAlias "$CA_ALIAS" -issuerKeyPwd "$P12_PWD" \
  -subject "C=CN,O=OpenHarmony,OU=HomeKiosk,CN=HomeKiosk App" \
  -validity 3650 -signAlg SHA256withECDSA \
  -issuerKeystoreFile "$SDK_P12" -issuerKeystorePwd "$P12_PWD" \
  -keystoreFile homekiosk.p12 -keystorePwd "$STORE_PWD" \
  -outForm certChain -rootCaCertFile root-ca.cer -subCaCertFile app-ca.cer \
  -outFile homekiosk-app.cer \
  | grep -iE 'success|fail|error' || true
[ -f homekiosk-app.cer ] || fail "没有生成 homekiosk-app.cer"
ok "chain 有 $(grep -c 'BEGIN CERT' homekiosk-app.cer) 张证书（leaf -> sub-CA -> root）"

step "4/5 写 Profile：bundle-name=$BUNDLE，有效期到 2033"
# cert 1 of the chain is the leaf; the profile must name exactly that one.
awk 'BEGIN{n=0} /BEGIN CERT/{n++} n==1{print > "app-leaf.pem"}' homekiosk-app.cer
"$OHOS_NODE" - "$SDK_PROF" "$BUNDLE" <<'NODE' || fail "node 生成 profile 失败"
const fs = require('fs');
const [src, bundle] = process.argv.slice(2);
const p = JSON.parse(fs.readFileSync(src, 'utf8'));
p['bundle-info']['bundle-name'] = bundle;
p['bundle-info']['distribution-certificate'] = fs.readFileSync('app-leaf.pem', 'utf8');
p['validity'] = { 'not-before': 1690000000, 'not-after': 2000000000 };
p.acls = { 'allowed-acls': [] };
fs.writeFileSync('homekiosk-profile.json', JSON.stringify(p, null, 4));
console.log('    bundle-name = ' + bundle + '  not-after = ' + new Date(p.validity['not-after'] * 1000).toISOString().slice(0, 10));
NODE

step "5/5 签名 Profile -> homekiosk-profile.p7b"
rm -f homekiosk-profile.p7b
sig sign-profile -mode localSign -keyAlias "$PROFILE_ALIAS" -keyPwd "$P12_PWD" \
  -profileCertFile "$SDK_PEM" -inFile homekiosk-profile.json \
  -signAlg SHA256withECDSA -keystoreFile "$SDK_P12" -keystorePwd "$P12_PWD" \
  -outFile homekiosk-profile.p7b \
  | grep -iE 'success|fail|error' || true

rm -f app-leaf.pem .c1.pem .c2.pem .c3.pem
echo
ok "签名材料齐了（signing/）"
echo "  keystore  $SIGN/homekiosk.p12   alias=$APP_ALIAS  pwd=$APP_PWD"
echo "  cert      $SIGN/homekiosk-app.cer"
echo "  profile   $SIGN/homekiosk-profile.p7b"
echo "  SDK p12   $SDK_P12  (public OpenHarmony test PKI, store pwd $P12_PWD)"
echo
echo "接着：bash scripts/sign.sh && bash scripts/deploy.sh"
