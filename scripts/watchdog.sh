#!/usr/bin/env bash
# External watchdog for the HomeKiosk info screen (host side, no device changes).
#
# What it does (one pass):
#   1. Ensures a device session exists (USB serial or OHOS_TARGET=ip:5555).
#   2. Restarts the kiosk app if it is not running (covers crash / kill -9 / reboot boot).
#   3. Appends an RSS sample (VmRSS) to the hourly log.
#   4. Once per local day, dumps hilog(fragment) + faultlog index into watchdog-logs/.
#
# Usage:
#   bash scripts/watchdog.sh --once      # single pass (for schtasks/cron)
#   bash scripts/watchdog.sh --loop 60   # run forever, check every 60 s
#
# Scheduled-task example (Windows, every 10 min):
#   schtasks /Create /TN "HomeKiosk-Watchdog" /SC MINUTE /MO 10 ^
#     /TR "\"C:\Program Files\Git\bin\bash.exe\" --login -i -c \"cd /d/ohos-kiosk && export OHOS_TARGET=192.168.x.x:5555 && bash scripts/watchdog.sh --once\""
#
# Exit codes: 0 ok; 1 device unreachable; 2 kiosk was down (restart issued); 3 app start failed.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ONCE=0
LOOP_SEC=0
case "${1:-}" in
  --once) ONCE=1 ;;
  --loop) LOOP_SEC="${2:-60}" ;;
  *) ONCE=1 ;;
esac

LOG_DIR="${WATCHDOG_LOG_DIR:-$PROJ_ROOT/watchdog-logs}"
BUNDLE="$(bundle_name 2>/dev/null || echo com.local.homekiosk)"
ABILITY="${OHOS_ABILITY:-EntryAbility}"
require_hdc

day_dir() {
  mkdir -p "$LOG_DIR/$(date +%F)"
  echo "$LOG_DIR/$(date +%F)"
}

device_alive() {
  list_targets | grep -q -v '^$'
}

kiosk_pid() {
  local pid
  pid="$(hdc_run shell pidof "$BUNDLE" 2>/dev/null | tr -d '\r\"')"; [ -n "$pid" ] || pid="$(hdc_run shell pgrep -f "$BUNDLE" 2>/dev/null | tr -d '\r\"')"
  echo "$pid"
}

sample_rss() {
  local log; log="$(day_dir)/rss.log"
  local pid; pid="$(kiosk_pid)"
  [ -n "$pid" ] || return 0
  local rss
  rss="$(hdc_run shell "cat /proc/$pid/status 2>/dev/null | grep VmRSS" | tr -d '\r')"
  [ -n "$rss" ] && printf '%s pid=%s %s\n' "$(date +%F_%T)" "$pid" "$rss" >> "$log"
}

daily_logs() {
  local stamp; stamp="$(date +%H%M)"
  [ "$stamp" != "0930" ] && return 0   # only at the 09:30 pass of the day scheduler
  local dir; dir="$(day_dir)"
  hdc_run shell hilog -x > "$dir/hilog-dump.txt" 2>/dev/null
  hdc_run shell "ls -la /data/log/faultlog/faultlogger 2>/dev/null" > "$dir/faultlog-index.txt" 2>/dev/null
  find "$LOG_DIR" -maxdepth 1 -type d -name '2*' -mtime +7 -exec rm -rf {} \; 2>/dev/null
}

one_pass() {
  if ! device_alive; then
    warn "设备不可达（USB 或 OHOS_TARGET）；本跳跳过"
    return 1
  fi

  if [ -z "$(kiosk_pid)" ]; then
    hdc_run shell power-shell wakeup >/dev/null 2>&1
    hdc_run shell aa start -a "$ABILITY" -b "$BUNDLE" >/dev/null 2>&1 || true
    sleep 3
    if [ -z "$(kiosk_pid)" ]; then ok "看门狗: 重启失败(?)"; return 3; fi
    ok "看门狗: 应用未在运行，已重新拉起"
  else
    ok "看门狗: 应用在运行 ($(kiosk_pid))"
  fi
  sample_rss
  daily_logs
  return 0
}

if [ "$ONCE" = 1 ]; then
  one_pass
  exit $?
fi

step "watchdog 循环模式（每 ${LOOP_SEC}s 一跳，Ctrl+C 退出）"
while true; do
  one_pass
  sleep "$LOOP_SEC"
done
