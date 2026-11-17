#!/usr/bin/env bash
# Environment / device / signing preflight. Run this before build.sh.
#   bash scripts/doctor.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PASS=0
MISS=0
mark_ok()   { ok "$*"; PASS=$((PASS+1)); }
mark_miss() { warn "$*"; MISS=$((MISS+1)); }

step "1. 构建主机基础工具"
NODE_FOUND="$(resolve_node || true)"
if [ -n "$NODE_FOUND" ]; then mark_ok "node -> $NODE_FOUND ($("$NODE_FOUND" -v 2>/dev/null))"; else mark_miss "node 未找到：hvigor 需要 Node.js（DevEco 自带 tools/node，或单独装 18+）"; fi
if "$JAVA_BIN" -version >/dev/null 2>&1; then
  mark_ok "java -> $JAVA_BIN ($("$JAVA_BIN" -version 2>&1 | head -1 | tr -d '"'))"
  case "$JAVA_BIN" in
    *"/C/"*|*"Program Files"*) mark_miss "java 在 C 盘：本机约定 JDK 只放 D 盘（JAVA_HOME=$JAVA_HOME）" ;;
  esac
else
  mark_miss "java 不可执行：$JAVA_BIN —— 签名工具需要 JDK（本机放 D:/ohos-tools/java/jdk-17）"
fi
if need git; then mark_ok "git $(git --version | awk '{print $3}')"; else mark_miss "git 未安装（CI 拉代码本身需要）"; fi

step "2. OpenHarmony SDK（API 10）"
TC="$OHOS_SDK_TOOLCHAINS"
if [ -d "$TC" ]; then
  mark_ok "toolchains -> $TC"
  AV=$(sed -n 's/.*"apiVersion": *"\([0-9]*\)".*/\1/p' "$TC/oh-uni-package.json" 2>/dev/null | head -1)
  VER=$(sed -n 's/.*"version": *"\([0-9.]*\)".*/\1/p' "$TC/oh-uni-package.json" 2>/dev/null | head -1)
  [ -n "$AV" ] && mark_ok "SDK apiVersion=$AV version=$VER" || mark_miss "读不到 $TC/oh-uni-package.json"
  [ -d "$OHOS_BASE_SDK_HOME/$AV" ] && mark_ok "hvigor 需要的版本号目录 $OHOS_BASE_SDK_HOME/$AV 存在" \
    || mark_miss "hvigor 按 API 号找目录：需要 $OHOS_BASE_SDK_HOME/$AV（指同一份 SDK 即可：powershell New-Item -ItemType Junction）"
  for c in ets js toolchains; do
    [ -d "$OHOS_BASE_SDK_HOME/openharmony/$c" ] && mark_ok "组件 $c" || mark_miss "缺组件 $c（native 只在有 C++ 代码时才需要）"
  done
else
  mark_miss "SDK toolchains 目录不存在：$TC —— 跑 bash scripts/get-ohos-sdk.sh"
fi

step "3. hdc 与签名工具（老开发板的兼容关键点）"
HDC_FOUND="$(resolve_hdc || true)"
[ -n "$HDC_FOUND" ] && mark_ok "hdc -> $HDC_FOUND ($("$HDC_FOUND" -v 2>/dev/null | head -1))" \
  || mark_miss "hdc 未找到。可从 Command Line Tools 的 toolchains 目录取，或 export HDC=/绝对路径/hdc(.exe)"
if [ -x "/d/DevEcoStudio/sdk/default/openharmony/toolchains/hdc.exe" ]; then
  mark_ok "备用 hdc（DevEco 26 自带）: $(/d/DevEcoStudio/sdk/default/openharmony/toolchains/hdc.exe -v 2>/dev/null | head -1)"
  echo "         若 IDE 认不到 4.0 板子，export HDC=<上面这个路径>，或反过来用 API10 那份"
fi
JAR_FOUND="$(resolve_sign_jar || true)"
if [ -n "$JAR_FOUND" ]; then
  mark_ok "hap-sign-tool -> $JAR_FOUND"
  [ -f "$(dirname "$JAR_FOUND")/OpenHarmony.p12" ] && mark_ok "SDK 自带 OpenHarmony 测试 PKI（make-signing-material.sh 用它签发应用证书）" \
    || mark_miss "SDK lib 下没有 OpenHarmony.p12，无法自签"
else
  mark_miss "hap-sign-tool.jar 未找到（在 SDK 的 toolchains/lib 下）"
fi

step "4. hvigor"
if [ -f hvigorw ] || [ -f hvigorw.bat ]; then
  mark_ok "hvigorw 存在（IDE 生成的工程包装器，优先用它）"
elif [ -f "${HVIGOR_CLI:-}" ] && [ -d "${NODE_PATH:-}" ]; then
  mark_ok "hvigor CLI -> $HVIGOR_CLI"
  echo "         hvigor-config.json5 里钉的版本：$(sed -n 's/.*"hvigorVersion": *"\([^"]*\)".*/\1/p' hvigor/hvigor-config.json5 2>/dev/null)"
else
  mark_miss "既没有 ./hvigorw 也没有 hvigor CLI：跑 bash scripts/install-hvigor.sh（装与 API 10 配套的 3.2.4）"
fi
[ -f hvigor/hvigor-config.json5 ] && mark_ok "hvigor/hvigor-config.json5 存在" || mark_miss "缺 hvigor/hvigor-config.json5"

step "5. 工程 API 配套"
grep -oE '"(compile|compatible)SdkVersion": *[0-9."]+' build-profile.json5 | tr -d ' ' | sed 's/^/         /'
echo "         实测板子为 OpenHarmony 4.1.7.5 / API 11（厂商 OHarm OS 2.0）；API 10 产物可直接装"
grep -q '"runtimeOS": *"OpenHarmony"' build-profile.json5 && mark_ok 'runtimeOS = OpenHarmony' || mark_miss 'build-profile.json5 里 runtimeOS 不是 OpenHarmony'

step "6. 设备在线与自证"
if [ -n "${HDC_FOUND:-}" ]; then
  HDC_BIN="$HDC_FOUND"
  DEV=$(list_targets | head -1)
  if [ -n "$DEV" ]; then
    mark_ok "设备在线: $DEV"
    export OHOS_TARGET="$DEV"
    # 不同镜像给的取属性工具不同：新镜像用 `param get`，老镜像用 `getparam`。
    dparam() {
      local k="$1" v
      v="$(hdc_run shell "param get $k" 2>/dev/null | tr -d '\r\n' | sed 's/ *$//')"
      case "$v" in *"not found"*|*inaccessible*|"") v="$(hdc_run shell "getparam $k" 2>/dev/null | tr -d '\r\n' | sed 's/ *$//')" ;; esac
      case "$v" in *"not found"*|*inaccessible*) v="" ;; esac
      printf '%s' "$v"
    }
    AV=$(dparam const.ohos.apiversion)
    PROJ_API=$(grep -oE '"compatibleSdkVersion": *"?[0-9]+' build-profile.json5 | grep -oE '[0-9]+$')
    if [ -n "$AV" ]; then
      mark_ok "设备 API version = $AV"
      if [ -n "$PROJ_API" ] && [ "$AV" -lt "$PROJ_API" ] 2>/dev/null; then
        mark_miss "设备 API $AV 低于工程 compatibleSdkVersion=$PROJ_API：装不上，改工程或换镜像"
      fi
    else
      mark_miss "读不到设备 API version（这个镜像可能既没有 param 也没有 getparam）"
    fi
    echo "         型号: $(dparam const.product.model)"
    echo "         系统: $(dparam const.ohos.fullname)"
  else
    mark_miss "没有在线设备：USB 连上并允许调试；或 bash scripts/tcp-mode.sh 后 OHOS_TARGET=<板子IP>:5555"
  fi
else
  mark_miss "没有 hdc，无法探测设备"
fi

step "7. 签名材料与 Profile 内容"
if [ -f "${OHOS_SIGN_DIR:-}/homekiosk.p12" ] && [ -f "${OHOS_SIGN_DIR:-}/homekiosk-app.cer" ] && [ -f "${OHOS_SIGN_DIR:-}/homekiosk-profile.p7b" ]; then
  mark_ok "三件套齐：$(ls "$OHOS_SIGN_DIR" | tr '\n' ' ')"
  if [ -n "$JAR_FOUND" ]; then
    PROF="$("$JAVA_BIN" -jar "$JAR_FOUND" verify-profile -inFile "$OHOS_SIGN_DIR/homekiosk-profile.p7b" 2>&1)"
    PB=$(echo "$PROF" | grep -oE '"bundle-name": *"[^"]+"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    NA=$(echo "$PROF" | grep -oE '"not-after": *[0-9]+' | head -1 | sed 's/[^0-9]//g')
    if [ "$PB" = "$OHOS_BUNDLE" ]; then mark_ok "Profile bundle-name = $PB（与工程一致）"
    else mark_miss "Profile bundle-name=$PB != 工程 $OHOS_BUNDLE —— 装上必报 9568322/9568313，重跑 make-signing-material.sh"; fi
    NOW=$(date +%s)
    [ -n "$NA" ] && [ "$NA" -gt "$NOW" ] && mark_ok "Profile 有效期到 $(date -d "@$NA" +%F 2>/dev/null || echo "$NA")" \
      || mark_miss "Profile 已过期或缺 not-after（当前 $(date +%F)）"
  fi
elif [ -d "${OHOS_SIGN_DIR:-}" ] && ls "$OHOS_SIGN_DIR"/*.p12 >/dev/null 2>&1; then
  warn "signing/ 有别的 .p12/.cer/.p7b（可能来自 IDE 自动签名），可用但未被本脚本命名约定识别"
  mark_ok "signing/ 里有材料：$(ls "$OHOS_SIGN_DIR" | tr '\n' ' ')"
else
  mark_miss "signing/ 缺材料：跑 bash scripts/make-signing-material.sh（用 SDK 自带的 OpenHarmony 测试 PKI 自签）"
fi

step "结果"
echo "         通过 $PASS 项，待补 $MISS 项"
if [ "$MISS" -gt 0 ]; then
  echo
  echo "补齐上面每一条提示后重跑 doctor.sh。链路本身（build -> sign）不依赖设备，"
  echo "只要 1-5、7 通过就能出包；第 6 项是上板前的最后一道。"
  exit 1
fi
exit 0
