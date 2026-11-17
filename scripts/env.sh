# Shared configuration for the OpenHarmony CI chain.
# Everything can be overridden by environment variables, so the same file works
# on a laptop (Git Bash), a self-hosted runner, or a container.
#
# Machine-specific paths do not belong in here: put them in scripts/env.local.sh
# (git-ignored), which is sourced first and therefore wins over every default.
ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_PROJ_ROOT="$(cd "$ENV_SH_DIR/.." && pwd)"
export OHOS_PROJECT_ROOT="$ENV_PROJ_ROOT"

# Sourced before the defaults below so a plain `export VAR=value` here wins.
[ -f "$ENV_SH_DIR/env.local.sh" ] && . "$ENV_SH_DIR/env.local.sh"

# --- Project identity -------------------------------------------------------
export OHOS_BUNDLE="${OHOS_BUNDLE:-com.local.homekiosk}"
export OHOS_ABILITY="${OHOS_ABILITY:-EntryAbility}"
export OHOS_MODULE="${OHOS_MODULE:-entry}"
export OHOS_PRODUCT="${OHOS_PRODUCT:-default}"
export OHOS_BUILD_MODE="${OHOS_BUILD_MODE:-debug}"

# --- Device targeting -------------------------------------------------------
# Either a USB serial (from `hdc list targets`) or "IP:PORT" for LAN deploys.
# Empty means: pick the first device hdc reports.
export OHOS_TARGET="${OHOS_TARGET:-}"
# Set to 1 to switch a USB-attached board into TCP mode once, so it can then be
# deployed from a machine that is not physically next to it.
export OHOS_TCP_PORT="${OHOS_TCP_PORT:-5555}"

# --- Toolchain discovery ----------------------------------------------------
# Root of an OpenHarmony SDK (the dir that contains openharmony/ toolchains/ etc).
export OHOS_SDK_HOME="${OHOS_SDK_HOME:-}"
# Explicit overrides if auto-detection picks the wrong one.
export HDC="${HDC:-}"
export HVIGORW="${HVIGORW:-}"
export HAP_SIGN_JAR="${HAP_SIGN_JAR:-}"

# --- This machine (verified 2026-11-14) -------------------------------------
# Everything below was installed on D: only. On another host, unset them and
# the auto-detection in common.sh takes over.
OHOS_TOOLS_ROOT="${OHOS_TOOLS_ROOT:-/d/ohos-tools}"
# The API 10 (OpenHarmony 4.0) app SDK, unpacked by scripts/get-ohos-sdk.sh.
export OHOS_BASE_SDK_HOME="${OHOS_BASE_SDK_HOME:-$OHOS_TOOLS_ROOT/sdk}"
export OHOS_SDK_TOOLCHAINS="${OHOS_SDK_TOOLCHAINS:-$OHOS_BASE_SDK_HOME/openharmony/toolchains}"
# hvigor 3.2.4 + @ohos/hvigor-ohos-plugin 3.2.4, npm-installed from
# https://repo.harmonyos.com/npm/ (registry.npmjs.org does not host them).
export OHOS_NODE_HOME="${OHOS_NODE_HOME:-/d/DevEcoStudio/tools/node}"
export HVIGOR_CLI="${HVIGOR_CLI:-$OHOS_TOOLS_ROOT/hvigor-3.2.4/node_modules/@ohos/hvigor/bin/hvigor-simple.js}"
export NODE_PATH="${NODE_PATH:-$OHOS_TOOLS_ROOT/hvigor-3.2.4/node_modules}"
export OHOS_NPM_REGISTRY="${OHOS_NPM_REGISTRY:-https://repo.harmonyos.com/npm/}"
# hvigor keeps its per-project workspace here; keep it off C: too.
export HVIGOR_USER_HOME="${HVIGOR_USER_HOME:-$OHOS_TOOLS_ROOT/hvigor-home}"

# Prefer an explicit JDK over whatever is on PATH. DevEco 26's own runtime (jbr)
# is Java 25 and is not what the sign tool was tested against; this machine has
# a D-drive JDK 17. hvigor also spawns bare `java`, so the bin dir must be on
# PATH during the build.
for _jh in "${JAVA_HOME:-}" "$OHOS_TOOLS_ROOT/java/jdk-17"; do
  if [ -n "$_jh" ] && [ -x "$_jh/bin/java.exe" ]; then
    export JAVA_HOME="${_jh//\\//}"
    case ":$PATH:" in
      *":$JAVA_HOME/bin:"*) ;;
      *) export PATH="$JAVA_HOME/bin:$PATH" ;;
    esac
    break
  fi
done
if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java.exe" ]; then
  export JAVA_BIN="${JAVA_BIN:-${JAVA_HOME}/bin/java.exe}"
elif [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
  export JAVA_BIN="${JAVA_BIN:-${JAVA_HOME}/bin/java}"
else
  export JAVA_BIN="${JAVA_BIN:-java}"
fi
# DevEco 26 also ships a matching node/ohpm/hvigor; useful when the system node
# is older than what the wrapper expects.
export DEVECO_HOME="${DEVECO_HOME:-/d/DevEcoStudio}"
export OHOS_NODE="${OHOS_NODE:-$DEVECO_HOME/tools/node/node.exe}"
export OHOS_OHPM="${OHOS_OHPM:-$DEVECO_HOME/tools/ohpm/bin/ohpm}"

# --- Signing materials ------------------------------------------------------
# Directory holding <keystore>.p12, <cert>.cer, <profile>.p7b for the board.
export OHOS_SIGN_DIR="${OHOS_SIGN_DIR:-$OHOS_PROJECT_ROOT/signing}"
export OHOS_KEYSTORE="${OHOS_KEYSTORE:-}"
export OHOS_APP_CERT="${OHOS_APP_CERT:-}"
export OHOS_PROFILE="${OHOS_PROFILE:-}"
export OHOS_KEY_ALIAS="${OHOS_KEY_ALIAS:-homekiosk-app-key-v1}"
# Passwords should come from the CI secret store, never from this file.
export OHOS_STORE_PWD="${OHOS_STORE_PWD:-123456}"
export OHOS_KEY_PWD="${OHOS_KEY_PWD:-123456}"

# --- Output -----------------------------------------------------------------
export OHOS_OUT_DIR="${OHOS_OUT_DIR:-$OHOS_PROJECT_ROOT/build-artifacts}"
export OHOS_UNSIGNED_HAP="${OHOS_UNSIGNED_HAP:-$OHOS_OUT_DIR/entry-unsigned.hap}"
export OHOS_SIGNED_HAP="${OHOS_SIGNED_HAP:-$OHOS_OUT_DIR/entry-signed.hap}"
export OHOS_SHOT="${OHOS_SHOT:-$OHOS_OUT_DIR/device.jpeg}"

# --- Photo push -------------------------------------------------------------
# Local drop folder; contents get copied to the app sandbox on the board.
export OHOS_PHOTO_SRC_DIR="${OHOS_PHOTO_SRC_DIR:-$OHOS_PROJECT_ROOT/assets/photos}"
