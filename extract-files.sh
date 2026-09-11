#!/usr/bin/env bash
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Extracts the proprietary blobs from the stock images mounted at /mnt/stock.
#
# Why from images and not from the device over adb, as the standard LineageOS
# script does: the images are the ones extracted from the phone's super in
# Phase 2 and match the stock firmware, whereas the device has been modified
# several times. The source is therefore more reliable and repeatable.
#
# A note on paths: system.img is system-as-root, so the files live under
# /mnt/stock/system/system/... while in the device tree the prefix is "system/".
set -euo pipefail

DEVICE=s88pro
VENDOR=doogee
SRC_SYSTEM=/mnt/stock/system
SRC_VENDOR=/mnt/stock/vendor
SRC_PRODUCT=/mnt/stock/product

# The product partition is not mounted (mounting it needs root) but its image
# is among the artefacts, and debugfs reads it without privileges. It is needed
# for libfmjni.so, which in the stock ROM lives in product/lib* and not system.
PRODUCT_IMG=/mnt/s88pro/gsi-work/product.img
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/../../../vendor/$VENDOR/$DEVICE/proprietary"

[ -d "$SRC_SYSTEM/system" ] || { echo "system.img not mounted at $SRC_SYSTEM" >&2; exit 1; }

mkdir -p "$DEST"
copied=0
missing=0

while read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  f="${line#-}"

  # "source:destination" syntax, as in LineageOS' extract_utils: it is needed
  # when a blob has to be installed under a different name. That happens here for
  # ims-common.jar, which becomes mtk-ims-compat.jar so as not to clash with the
  # ims-common.jar we build ourselves and that the framework needs.
  case "$f" in
    *:*) dst="${f#*:}"; f="${f%%:*}" ;;
    *)   dst="$f" ;;
  esac

  # Files in product are taken from the image with debugfs when the partition is
  # not mounted: inside the image the path has no "product/" prefix.
  case "$f" in
    product/*)
      if [ -d "$SRC_PRODUCT" ]; then
        src="$SRC_PRODUCT/${f#product/}"
      elif [ -f "$PRODUCT_IMG" ]; then
        mkdir -p "$DEST/$(dirname "$dst")"
        if debugfs -R "dump /${f#product/} $DEST/$dst" "$PRODUCT_IMG" 2>/dev/null \
             && [ -s "$DEST/$dst" ]; then
          copied=$((copied+1))
        else
          echo "MISSING: $f  (not extracted from $PRODUCT_IMG)" >&2
          missing=$((missing+1))
        fi
        continue
      else
        src=""
      fi
      ;;
    system/*) src="$SRC_SYSTEM/$f" ;;
    vendor/*) src="$SRC_VENDOR/${f#vendor/}" ;;
    *)        src="$SRC_SYSTEM/$f" ;;
  esac

  if [ -n "$src" ] && [ -f "$src" ]; then
    mkdir -p "$DEST/$(dirname "$dst")"
    cp -a "$src" "$DEST/$dst"
    copied=$((copied+1))
  else
    echo "MISSING: $f  (looked for in $src)" >&2
    missing=$((missing+1))
  fi
done < "$HERE/proprietary-files.txt"

echo "blobs copied: $copied, missing: $missing"
echo "destination: $DEST"
[ "$missing" -eq 0 ] || exit 1
