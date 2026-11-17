#!/usr/bin/env bash
# Push local photos into the app's sandbox so the photo card has something to show.
#   bash scripts/push-photos.sh [目录]
# The sandbox path is per-user (el2/100). If the image blocks non-root writes the
# script tells you the exact manual step instead of silently doing nothing.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SRC="${1:-$OHOS_PHOTO_SRC_DIR}"
[ -d "$SRC" ] || fail "照片目录不存在：$SRC（默认 assets/photos，可传第一个参数指定）"

mapfile -t FILES < <(find "$SRC" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' \) | sort)
[ "${#FILES[@]}" -gt 0 ] || fail "$SRC 里没有图片文件"
ok "准备推送 ${#FILES[@]} 张"

require_device
# 应用沙箱实际在 .../base/<bundle>/haps/<module>/files（不是 .../files）。
# 模块名随工程变，优先探测已存在的目录，找不到再按 entry 拼。
SANDBOX=""
for cand in $(hdc_run shell "ls -d /data/app/el2/100/base/$OHOS_BUNDLE/haps/*/files/photos 2>/dev/null" | tr -d '\r'); do
  SANDBOX="$cand"; break
done
[ -n "$SANDBOX" ] || SANDBOX="/data/app/el2/100/base/$OHOS_BUNDLE/haps/entry/files/photos"

step "尝试直写应用沙箱 $SANDBOX"
if hdc_run shell "mkdir -p $SANDBOX" >/dev/null 2>&1; then
  FAILS=0
  for f in "${FILES[@]}"; do
    # 两个坑：(1) Git Bash 会把远端 /data/... 改写成 Windows 路径；
    # (2) 这版 hdc 的 file send 会按本地相对路径在远端建子目录，所以先 cd 到图片目录只发文件名。
    if ( cd "$(dirname "$f")" && MSYS_NO_PATHCONV=1 hdc_run file send "./$(basename "$f")" "$SANDBOX/" >/dev/null 2>&1 ); then
      ok "-> $(basename "$f")"
    else
      FAILS=$((FAILS+1))
    fi
  done
  if [ "$FAILS" -eq 0 ]; then
    # root 写进去的文件属主是 root，应用(200xxxxx)读不了；改成 files 目录同属主。
    OWNER="$(hdc_run shell "stat -c '%u:%g' $(dirname "$SANDBOX")" 2>/dev/null | tr -d '\r')"
    [ -n "$OWNER" ] && hdc_run shell "chown $OWNER $SANDBOX/*.jpg $SANDBOX/*.jpeg $SANDBOX/*.png $SANDBOX/*.webp $SANDBOX/*.bmp $SANDBOX/*.gif 2>/dev/null; chmod 660 $SANDBOX/*.jpg $SANDBOX/*.jpeg $SANDBOX/*.png $SANDBOX/*.webp $SANDBOX/*.bmp $SANDBOX/*.gif 2>/dev/null" >/dev/null 2>&1
    ok "全部写入 $SANDBOX"
    echo "     在板子上打开 HomeKiosk（或 bash scripts/deploy.sh 重启）即可看到轮播。"
    exit 0
  fi
  warn "有 $FAILS 张直写沙箱失败"
else
  warn "无法创建沙箱目录（权限受限）"
fi

step "退到 /data/local/tmp 暂存"
TMP="/data/local/tmp/photos"
hdc_run shell "mkdir -p $TMP" >/dev/null 2>&1
for f in "${FILES[@]}"; do
  ( cd "$(dirname "$f")" && MSYS_NO_PATHCONV=1 hdc_run file send "./$(basename "$f")" "$TMP/" >/dev/null 2>&1 ) && ok "staged $(basename "$f")" || warn "send 失败 $(basename "$f")"
done

echo
echo "图片已放在设备 $TMP。最后一步需要 root（开发者版镜像一般可开）："
echo "    hdc shell"
echo "    cp $TMP/* $SANDBOX/ && chown 20010025:20010025 $SANDBOX/* && chmod 660 $SANDBOX/*"
echo
echo "不想动 root 的话，替代方案是用 DevEco Studio 的 Device File Browser 把图拖进"
echo "$SANDBOX/，页面刷新后生效（Index 的 onPageShow 会重新列目录）。"
