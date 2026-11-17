# Common helpers. Sourced by every script in this folder.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJ_ROOT"
# shellcheck source=env.sh
. "$SCRIPT_DIR/env.sh"

step()  { printf '\n\033[1;36m==> %b\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m[ ok ]\033[0m %b\n' "$*"; }
warn()  { printf '\033[1;33m[warn ]\033[0m %b\n' "$*"; }
fail()  { printf '\033[1;31m[fail ]\033[0m %b\n' "$*"; exit 1; }
need()  { command -v "$1" >/dev/null 2>&1; }

# Candidates for an OpenHarmony SDK root, most specific first.
sdk_candidates() {
  [ -n "${OHOS_SDK_HOME:-}" ] && echo "$OHOS_SDK_HOME"
  [ -n "${OHOS_BASE_SDK_HOME:-}" ] && echo "$OHOS_BASE_SDK_HOME"
  [ -n "${DEVECO_SDK_HOME:-}" ] && echo "$DEVECO_SDK_HOME"
  echo "$HOME/.ohos/sdk"
  echo "$HOME/AppData/Local/OpenHarmony/Sdk"
  echo "/c/Program Files/Huawei/DevEco Studio/sdk"
  echo "/d/Program Files/Huawei/DevEco Studio/sdk"
  echo "/c/OpenHarmony/Sdk"
  # DevEco 26 silent install to a custom root, and the standalone OHOS SDK
  # unpacked by scripts/get-ohos-sdk.sh. Both live on D: on this machine.
  ls -d /d/DevEcoStudio/sdk/* 2>/dev/null
  ls -d "${DEVECO_HOME:-/d/DevEcoStudio}"/sdk/* 2>/dev/null
  ls -d /d/ohos-tools/sdk/* 2>/dev/null
  ls -d /c/Program\ Files/Huawei/DevEco*/sdk/* 2>/dev/null
  ls -d "$HOME"/AppData/Local/OpenHarmony/Sdk/* 2>/dev/null
}

# Find a file inside the SDK: find_in_sdk toolchains/hdc.exe
find_in_sdk() {
  local rel="$1" cand
  while IFS= read -r cand; do
    [ -z "$cand" ] && continue
    [ ! -e "$cand" ] && continue
    if [ -f "$cand/$rel" ]; then echo "$cand/$rel"; return 0; fi
    # DevEco nests the SDK under default/openharmony or <ver>/openharmony
    local nested
    for nested in "$cand"/default/openharmony "$cand"/*/openharmony "$cand"/openharmony; do
      if [ -f "$nested/$rel" ]; then echo "$nested/$rel"; return 0; fi
    done
  done < <(sdk_candidates)
  return 1
}

# Echo a usable node binary: DevEco's bundled node, then system node.
resolve_node() {
  if [ -n "${OHOS_NODE:-}" ] && [ -x "${OHOS_NODE}" ]; then echo "$OHOS_NODE"; return 0; fi
  local c
  for c in "$OHOS_NODE" /d/DevEcoStudio/tools/node/node.exe \
           "/c/Program Files/Huawei/DevEco Studio/tools/node/node.exe"; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  need node && { echo "node"; return 0; }
  return 1
}

resolve_hdc() {  if [ -n "${HDC:-}" ] && [ -x "$HDC" ]; then echo "$HDC"; return 0; fi
  if need hdc.exe || need hdc; then
    if need hdc; then echo "hdc"; return 0; fi
    echo "hdc.exe"; return 0
  fi
  find_in_sdk "toolchains/hdc.exe" || find_in_sdk "toolchains/hdc"
}

resolve_sign_jar() {
  if [ -n "${HAP_SIGN_JAR:-}" ] && [ -f "$HAP_SIGN_JAR" ]; then echo "$HAP_SIGN_JAR"; return 0; fi
  find_in_sdk "toolchains/lib/hap-sign-tool.jar"
}

# Echo the target to use; empty means "let hdc pick the only device".
target_flag() {
  if [ -n "${OHOS_TARGET:-}" ]; then echo "-t $OHOS_TARGET"; else echo ""; fi
}

hdc_run() {
  local tf; tf="$(target_flag)"
  if [ -n "$tf" ]; then
    # shellcheck disable=SC2086
    "$HDC_BIN" $tf "$@"
  else
    "$HDC_BIN" "$@"
  fi
}

require_hdc() {
  HDC_BIN="$(resolve_hdc || true)"
  [ -n "${HDC_BIN:-}" ] || fail "hdc not found. Set OHOS_SDK_HOME or HDC=/path/to/hdc(.exe). Run scripts/doctor.sh for the full checklist."
  HDC_BIN="${HDC_BIN//\\//}"
  "$HDC_BIN" -v >/dev/null 2>&1 || warn "hdc found at $HDC_BIN but '-v' failed; check driver/USB permissions."
  ok "hdc: $("$HDC_BIN" -v 2>/dev/null | head -1)  ($HDC_BIN)"
}

list_targets() {
  "$HDC_BIN" list targets 2>/dev/null | tr -d '\r' | grep -v -E '^\[Empty\]$|^$' || true
}

require_device() {
  require_hdc
  local targets; targets="$(list_targets)"
  if [ -z "$targets" ]; then
    warn "没有在线设备。"
    echo "  USB:      插上板子，开发者选项里开 USB 调试并同意弹窗，然后：hdc list targets"
    echo "            列不出来就换一份 hdc（SDK 里 1.3.0a / DevEco 里 3.2.0f，两份都已装好）"
    echo "  局域网:   趁线还插着跑一次 scripts/tcp-mode.sh"
    echo "            之后任何能路由到该 IP 的机器都能部署：OHOS_TARGET=192.168.x.x:5555"
    fail "中止：没有目标设备"
  fi
  ok "devices online:"
  echo "$targets" | sed 's/^/         /'
  if [ -z "${OHOS_TARGET:-}" ]; then
    OHOS_TARGET="$(echo "$targets" | head -1 | awk '{print $1}')"
    export OHOS_TARGET
  fi
  ok "using target: $OHOS_TARGET"
}
