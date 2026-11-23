#!/usr/bin/env bash
# Install + launch + verify on the board (USB or LAN, no IDE).
#   bash scripts/deploy.sh
#   OHOS_TARGET=192.168.1.23:5555 bash scripts/deploy.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_device

[ -f "$OHOS_SIGNED_HAP" ] || fail "找不到 $OHOS_SIGNED_HAP。先跑 build.sh（若产物未签名再跑 sign.sh）"

step "安装 HAP（-r 覆盖安装，保留 filesDir 收件箱）"
# hdc on Windows mishandles some absolute paths; install from the file's directory.
HAP_DIR="$(dirname "$OHOS_SIGNED_HAP")"; HAP_NAME="$(basename "$OHOS_SIGNED_HAP")"
install_hap() {
  ( cd "$HAP_DIR" && \
    if [ -n "$OHOS_TARGET" ]; then "$HDC_BIN" -t "$OHOS_TARGET" install -r "$HAP_NAME"; else "$HDC_BIN" install -r "$HAP_NAME"; fi )
}
ERR_HINT="安装失败。按错误码排查：\n     9568322/9568313 签名或 Profile 与设备/包名不匹配 -> signing/README.md\n     9568289 签名材料不成套\n     InstallFailed.*api version 应用要求的 API 高于设备 -> 改 build-profile.json5 的 compatibleSdkVersion\n     [Fail]Connect  设备掉线 -> 重新 hdc tconn 或插拔 USB"

OUT="$(install_hap 2>&1 || true)"
printf '%s\n' "$OUT" | sed 's/^/         /'
# hdc 即使 install 失败也可能返回 0：必须看输出里的 msg:error，不能只看退出码。
if printf '%s\n' "$OUT" | grep -q 'msg:error'; then
  warn "覆盖安装被拒（常见：debug/release 类型不一致）。卸载后重装：filesDir（含收件箱）会被清空"
  hdc_run uninstall "$OHOS_BUNDLE" >/dev/null 2>&1 || true
  OUT="$(install_hap 2>&1 || true)"
  printf '%s\n' "$OUT" | sed 's/^/         /'
  printf '%s\n' "$OUT" | grep -q 'msg:error' && fail "$ERR_HINT"
fi
printf '%s\n' "$OUT" | grep -qi 'successfully' || fail "$ERR_HINT"
ok "installed"

step "启动 EntryAbility"
hdc_run shell "aa start -a $OHOS_ABILITY -b $OHOS_BUNDLE" || fail "启动失败：确认 module.json5 里 abilities 名与 OHOS_ABILITY=$OHOS_ABILITY 一致"
sleep 3

step "运行状态判定"
PID=$(hdc_run shell "pidof $OHOS_BUNDLE" 2>/dev/null | tr -d '\r')
if [ -n "$PID" ]; then ok "进程存活 pid=$PID"; else warn "pidof 读不到进程，可能已崩溃，看下面的日志"; fi

step "截图（UI 是否真渲染）"
mkdir -p "$OHOS_OUT_DIR"
hdc_run shell "rm -f /data/local/tmp/kiosk.jpeg" >/dev/null 2>&1
if hdc_run shell "snapshot_display -f /data/local/tmp/kiosk.jpeg" >/dev/null 2>&1; then
  rm -f "$OHOS_SHOT"
  # Git Bash (MSYS) rewrites `/data/...` into a Windows path and hands hdc.exe a
  # POSIX destination it cannot open. Disable arg conversion for the device path
  # and pass a native absolute path for the destination where cygpath exists.
  LOCAL_SHOT="$OHOS_SHOT"
  command -v cygpath >/dev/null 2>&1 && LOCAL_SHOT="$(cygpath -w "$OHOS_SHOT")"
  if MSYS_NO_PATHCONV=1 hdc_run file recv /data/local/tmp/kiosk.jpeg "$LOCAL_SHOT" >/dev/null 2>&1 && [ -s "$OHOS_SHOT" ]; then
    ok "截图 -> $OHOS_SHOT"
  else
    warn "截图已生成但拉取失败（可手动：hdc file recv /data/local/tmp/kiosk.jpeg .）"
  fi
else
  warn "snapshot_display 不可用：换 `hdc shell snapshot_display -f /data/local/tmp/kiosk.png` 或在 DevEco 里看设备投屏"
fi

step "关键日志 / 崩溃线索"
hdc_run shell "hilog -x -T HomeTransfer | tail -n 25" 2>/dev/null | tr -d '\r' | sed 's/^/         /' || true
hdc_run shell "ls -t /data/log/faultlog/faultlogger 2>/dev/null | head -n 3" 2>/dev/null | tr -d '\r' | sed 's/^/    crash: /' || true

step "完成"
echo "     bundle : $OHOS_BUNDLE"
echo "     target : $OHOS_TARGET"
echo "     照片推送: bash scripts/push-photos.sh"
[ -n "${PID:-}" ] || exit 1
