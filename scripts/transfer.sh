#!/usr/bin/env bash
# HomeTransfer hdc 兜底互传（不依赖 App 服务、不依赖同网段）
#
#   bash scripts/transfer.sh list
#   bash scripts/transfer.sh push D:/path/file.zip
#   bash scripts/transfer.sh push D:/path/file.zip renamed.zip
#   bash scripts/transfer.sh pull renamed.zip D:/downloads
#   bash scripts/transfer.sh open
#
# 前提：设备已开 USB 调试（或 OHOS_TARGET=ip:5555），本机 hdc 可列到设备。
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"
require_hdc
require_device

BUNDLE="com.local.transfer"
INBOX="/data/app/el2/100/base/$BUNDLE/haps/entry/files/inbox"
TMP="/data/local/tmp/osx_transfer_upload"

ensure_inbox() {
  hdc_run shell "mkdir -p '$INBOX'" >/dev/null 2>&1
}

cmd="${1:-list}"
case "$cmd" in
  list)
    ensure_inbox
    hdc_run shell "ls -l '$INBOX'"
    ;;
  push)
    src="${2:-}"
    name="${3:-}"
    [ -n "$src" ] || fail "用法: transfer.sh push <本地文件> [手机上的文件名]"
    [ -f "$src" ] || fail "本地文件不存在: $src"
    [ -n "$name" ] || name="$(basename "$src")"
    ensure_inbox
    step "推送到收件箱: $name"
    hdc_run file send "$src" "$TMP"
    hdc_run shell "cp '$TMP' '$INBOX/$name'"
    hdc_run shell "chown \$(stat -c %u '$INBOX'):\$(stat -c %g '$INBOX') '$INBOX/$name' && chmod 660 '$INBOX/$name'"
    hdc_run shell "rm -f '$TMP'"
    ok "已推送 -> $INBOX/$name"
    ;;
  pull)
    name="${2:-}"
    dest="${3:-.}"
    [ -n "$name" ] || fail "用法: transfer.sh pull <手机上的文件名> [本地目录]"
    mkdir -p "$dest"
    step "拉取: $name"
    hdc_run file recv "$INBOX/$name" "$dest/$name"
    ok "已拉取 -> $dest/$name"
    ;;
  open)
    hdc_run shell aa start -a EntryAbility -b "$BUNDLE" >/dev/null 2>&1
    ok "已尝试打开快传"
    ;;
  *)
    echo "用法: transfer.sh {list|push|pull|open} ..." >&2
    exit 2
    ;;
esac
