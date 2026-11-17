#!/usr/bin/env bash
# Flip the SDK version the project compiles against, e.g. after reflashing the board.
#   bash scripts/set-api.sh 10            # OpenHarmony 4.0 (factory image)
#   bash scripts/set-api.sh 12            # OpenHarmony 5.0
#   bash scripts/set-api.sh "4.0.0(10)"   # exact DevEco 26.x string form
#   bash scripts/set-api.sh "5.0.0(12)"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

V="${1:?用法: bash scripts/set-api.sh 10  或  \"4.0.0(10)\"}"

# Both forms are written as quoted strings; DevEco 26.x projects use "4.0.0(10)"
# style while OpenHarmony 3.x/4.x templates accept the bare "10". align-toolchain.sh
# --sync-sdk overwrites these with whatever your reference project uses.
value="\"$V\""

for key in compileSdkVersion compatibleSdkVersion targetSdkVersion; do
  if grep -q "\"$key\"" build-profile.json5; then
    sed -i -E "s/(\"$key\": *)\"?[0-9.()a-zA-Z]+\"?/\1$value/" build-profile.json5
  fi
done

step "已写入的 SDK 版本"
grep -nE 'compileSdkVersion|compatibleSdkVersion|targetSdkVersion|runtimeOS' build-profile.json5 | sed 's/^/     /'
echo
echo "提醒：改完还要确认本机装了配套 SDK（DevEco -> Settings -> OpenHarmony SDK），"
echo "     并用 bash scripts/align-toolchain.sh -ref <空白工程> --sync-sdk 对齐工程格式。"
echo "     目标设备 API 必须 >= 这里的数字，否则安装会报 api version 相关错误。"
