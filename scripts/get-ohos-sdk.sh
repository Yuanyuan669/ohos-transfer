#!/usr/bin/env bash
# Download and unpack the official OpenHarmony app-side SDK for a chosen release.
#
# Why this exists: DevEco Studio ships only the SDK version it was built against
# (26.0.1.x here). A board running OpenHarmony 4.0 needs API 10, and the board
# does not have to be attached to the machine that builds. So the SDK is pulled
# straight from the OpenHarmony mirror instead of through the IDE wizard, which
# makes the same step reproducible on a CI server.
#
# Usage:
#   scripts/get-ohos-sdk.sh                    # 4.0-Release (API 10) -> /d/ohos-tools/sdk
#   scripts/get-ohos-sdk.sh 4.1-Release        # API 11
#   scripts/get-ohos-sdk.sh 5.0.0-Release      # API 12
#
# The download is ~2 GB; it is verified against the published .sha256 before
# anything is unpacked.
set -euo pipefail

RELEASE="${1:-4.0-Release}"
DEST_ROOT="${OHOS_SDK_INSTALL_ROOT:-/d/ohos-tools/sdk}"
BASE="https://repo.huaweicloud.com/openharmony/os/${RELEASE}"
ARCHIVE="ohos-sdk-windows_linux-public.tar.gz"
DEST="$DEST_ROOT/openharmony-${RELEASE}"

command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }

mkdir -p "$DEST_ROOT"
cd "$DEST_ROOT"

# Reuse a download that a previous run left one level up (that is where the
# manual bootstrap put it), so re-running never costs 2 GB again.
if [ ! -f "$ARCHIVE" ] && [ -f "$DEST_ROOT/../$ARCHIVE" ]; then
  echo "==> reusing $DEST_ROOT/../$ARCHIVE"
  mv "$DEST_ROOT/../$ARCHIVE" "$ARCHIVE"
fi

echo "==> fetching checksum for $RELEASE"
SHA="$(curl -fsSL --max-time 60 "$BASE/$ARCHIVE.sha256" | tr -d ' \r\n')"
[ -n "$SHA" ] || { echo "could not read $BASE/$ARCHIVE.sha256"; exit 1; }
echo "    expected: $SHA"

if [ ! -f "$ARCHIVE" ]; then
  echo "==> downloading $BASE/$ARCHIVE (~2 GB)"
  curl -fSL --retry 5 --retry-delay 5 --connect-timeout 20 -o "$ARCHIVE.part" "$BASE/$ARCHIVE"
  mv "$ARCHIVE.part" "$ARCHIVE"
else
  echo "==> archive already present, verifying"
fi

echo "==> verifying sha256"
echo "$SHA *$ARCHIVE" | sha256sum -c -

if [ ! -d "$DEST" ]; then
  echo "==> unpacking into $DEST"
  TMP="$(mktemp -d)"
  tar -xf "$ARCHIVE" -C "$TMP"
  # The tarball holds ohos-sdk/{windows,linux}/<component>.zip; take windows.
  WIN="$(find "$TMP" -maxdepth 3 -type d -name windows | head -1)"
  [ -n "$WIN" ] || { echo "no windows/ directory in the archive"; ls -R "$TMP" | head -40; rm -rf "$TMP"; exit 1; }
  mkdir -p "$DEST"
  for z in "$WIN"/*.zip; do
    echo "    $(basename "$z")"
    unzip -q -o "$z" -d "$DEST"
  done
  rm -rf "$TMP"
else
  echo "==> $DEST already unpacked, skipping"
fi

echo
echo "==> SDK layout"
ls "$DEST"
for need in toolchains/hdc.exe toolchains/lib/hap-sign-tool.jar ets/oh-uni-package.json; do
  if [ -e "$DEST/$need" ]; then echo "    [ ok ] $need"; else echo "    [warn] missing $need"; fi
done

# hvigor looks components up as $OHOS_BASE_SDK_HOME/<apiVersion>/<component>, so
# it needs a directory literally named after the API level. A link costs nothing.
APIVER="$(sed -n 's/.*"apiVersion": *"\([0-9]*\)".*/\1/p' "$DEST/toolchains/oh-uni-package.json" 2>/dev/null | head -1)"
if [ -n "$APIVER" ] && [ ! -e "$DEST_ROOT/$APIVER" ]; then
  echo "==> linking $DEST_ROOT/$APIVER -> $DEST (hvigor 按 API 号找组件)"
  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$DEST_ROOT/$APIVER")' -Target '$(cygpath -w "$DEST")' | Out-Null" \
      && echo "    [ ok ] junction created" || echo "    [warn] junction failed; create it yourself"
  else
    ln -s "$DEST" "$DEST_ROOT/$APIVER" && echo "    [ ok ] symlink created"
  fi
fi
# Also expose the conventional name used by DevEco's layout.
[ -e "$DEST_ROOT/openharmony" ] || ln -s "$DEST" "$DEST_ROOT/openharmony" 2>/dev/null || \
  powershell.exe -NoProfile -Command "New-Item -ItemType Junction -Path '$(cygpath -w "$DEST_ROOT/openharmony")' -Target '$(cygpath -w "$DEST")' | Out-Null" 2>/dev/null

echo
echo "Next: point the build at it"
echo "  export OHOS_BASE_SDK_HOME=$DEST_ROOT"
echo "  export OHOS_SDK_TOOLCHAINS=$DEST/toolchains"
echo "  bash scripts/install-hvigor.sh && bash scripts/doctor.sh"
