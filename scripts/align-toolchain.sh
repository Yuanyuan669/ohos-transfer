#!/usr/bin/env bash
# Copy the version-specific build wrapper out of a DevEco Studio generated
# project into this hand-written one, so hvigor matches the installed IDE exactly.
#
#   1) DevEco Studio -> New Project -> Empty Ability -> OpenHarmony App
#      (same device type as your board, finish without running it)
#   2) bash scripts/align-toolchain.sh -ref "C:/Users/you/DevEcoStudioProjects/MyApp" --sync-sdk
#
# --sync-sdk also rewrites compileSdkVersion / compatibleSdkVersion / runtimeOS
# in ./build-profile.json5 from the reference project.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

REF=""
SYNC_SDK=0
while [ $# -gt 0 ]; do
  case "$1" in
    -ref|--ref) REF="${2:?需要跟一个工程目录}"; shift 2 ;;
    --sync-sdk) SYNC_SDK=1; shift ;;
    *) fail "未知参数: $1（用法见脚本头部注释）" ;;
  esac
done
[ -n "$REF" ] || fail "必须给 -ref <DevEco 生成的工程目录>"
[ -d "$REF" ] || fail "目录不存在: $REF"
[ -f "$REF/build-profile.json5" ] || fail "$REF 不像一个 DevEco/OpenHarmony 工程（缺 build-profile.json5）"

step "从参考工程复制构建包装器"
copy_one() { # $1 relative path, $2 required(1)/optional(0)
  if [ -f "$REF/$1" ]; then
    mkdir -p "$(dirname "$1")"
    cp -f "$REF/$1" "$1"
    case "$1" in hvigorw|*.sh) chmod +x "$1" 2>/dev/null ;; esac
    ok "copied $1"
  elif [ "$2" = "1" ]; then
    warn "参考工程里没有 $1（正常，Windows 工程可能只有 hvigorw.bat）"
  fi
}
copy_one hvigorw 0
copy_one hvigorw.bat 0
copy_one hvigor/hvigor-wrapper.js 0
copy_one hvigor/hvigor-config.json5 1
copy_one hvigor/hvigor-wrapper.json5 0
copy_one oh-package.json5 1
copy_one hvigorfile.ts 1
copy_one entry/hvigorfile.ts 1

if [ ! -f hvigorw ] && [ ! -f hvigorw.bat ]; then
  fail "参考工程里既没有 hvigorw 也没有 hvigorw.bat。请确认那个工程能独立打开并构建。"
fi

if [ "$SYNC_SDK" = "1" ]; then
  step "同步 SDK 版本"
  for key in compileSdkVersion compatibleSdkVersion; do
    VAL=$(grep -oE "\"$key\": *\"?[^,\"}]+\"?" "$REF/build-profile.json5" | head -1 | sed -E 's/.*: *"?([^,"}]*)"?.*/\1/')
    if [ -n "$VAL" ]; then
      sed -i -E "s/(\"$key\": *)\"?[0-9.]+\"?/\1\"$VAL\"/" build-profile.json5
      ok "$key -> $VAL"
    else
      warn "参考工程里没解析到 $key"
    fi
  done
  RT=$(grep -oE '"runtimeOS": *"[^"]+"' "$REF/build-profile.json5" | head -1 | sed -E 's/.*: *"([^"]+)"/\1/')
  if [ -n "$RT" ]; then
    sed -i -E "s/(\"runtimeOS\": *)\"[^\"]+\"/\1\"$RT\"/" build-profile.json5
    ok "runtimeOS -> $RT"
  fi
  grep -nE 'compileSdkVersion|compatibleSdkVersion|runtimeOS' build-profile.json5 | sed 's/^/         /'
fi

step "对齐后请确认"
cat <<'EOF'
     - 本工程用的是手写的 hvigorfile.ts / oh-package.json5，若参考工程内容不同
       （比如新版 DevEco 用 "modelVersion" 字段），已按参考工程覆盖。
     - 签名相关一律留空（build-profile.json5 的 signingConfigs: []），
       这样 CI 走 scripts/sign.sh 的命令行签名，不依赖 IDE。
     - 现在跑: bash scripts/doctor.sh
EOF
