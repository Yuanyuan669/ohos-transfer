#!/usr/bin/env bash
# Switch a USB-attached board into hdc TCP mode, then print the exact command
# any other machine (or CI runner) on the same network needs to deploy it.
#   bash scripts/tcp-mode.sh          # once, while the board is plugged in
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_device

step "开启设备 TCP 监听端口 $OHOS_TCP_PORT"
hdc_run tmode port "$OHOS_TCP_PORT" || warn "tmode 不可用（部分镜像只允许在开发者选项里开无线调试）。请在板子上：设置 -> 系统 -> 开发者选项 -> 打开 USB 调试/无线调试"
sleep 1

step "取设备 IP"
IP=""
for cmd in "ifconfig wlan0" "ip addr show wlan0" "netmask"; do
  OUT=$(hdc_run shell "$cmd" 2>/dev/null | tr -d '\r')
  CAND=$(echo "$OUT" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '^127\.' | head -1)
  if [ -n "$CAND" ]; then IP="$CAND"; break; fi
done
[ -n "$IP" ] || fail "读不到 wlan0 地址：确认板子已连 Wi-Fi（或插入 SIM 后走 rmnet0，把上面命令里的网卡名换掉再跑）"
ok "设备 IP: $IP"

step "验证网络直连"
"$HDC_BIN" tconn "$IP:$OHOS_TCP_PORT" && sleep 1 && "$HDC_BIN" list targets | sed 's/^/         /'

echo
echo "以后任何一台能路由到 $IP 的机器都可以直接部署，不需要插线："
echo "    export OHOS_TARGET=$IP:$OHOS_TCP_PORT"
echo "    bash scripts/pipeline.sh"
echo
echo "在 CI 里把 OHOS_TARGET 作为变量配置即可（见 ci/*.yml）。IP 变了就重跑本脚本。"
