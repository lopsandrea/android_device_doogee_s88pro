#!/bin/bash
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Prepares ImsService.apk for VoLTE: disassembles the stock ROM's dex, applies
# the patches in patches/, reassembles and aligns. Signing is NOT done here:
# the build system takes care of it, because Android.mk declares
# LOCAL_CERTIFICATE := platform. The platform key is needed because the APK
# uses sharedUserId="android.uid.phone" and has to share the UID with com.android.phone.
#
# Usage:
#   ./prepare-imsservice.sh /path/to/stock/rom/system/priv-app/ImsService/ImsService.apk
#
# The result is ImsService.apk in this directory, which device.mk installs as
# priv-app if it finds it. Without it, the build carries on without VoLTE.
#
# The status of this work -- what works and what does not -- is in
# docs/bringup/volte-stato-esperimento.md

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:?the path to the stock ImsService.apk is required}"
OUT="$DIR/ImsService.apk"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

: "${ANDROID_BUILD_TOP:?run first: source build/envsetup.sh && lunch lineage_s88pro-userdebug}"

JAVA="$ANDROID_BUILD_TOP/prebuilts/jdk/jdk11/linux-x86/bin/java"
SMALI_DIR="$ANDROID_BUILD_TOP/prebuilts/extract-tools/common/smali"
ZIPALIGN="$ANDROID_BUILD_TOP/out/soong/host/linux-x86/bin/zipalign"

echo "== extracting the dex from $SRC"
unzip -o -q "$SRC" "classes*.dex" -d "$WORK"
[ -f "$WORK/classes2.dex" ] && { echo "expected a single dex, this APK has more than one"; exit 1; }

echo "== disassembling"
"$JAVA" -Xmx3g -jar "$SMALI_DIR/baksmali.jar" d "$WORK/classes.dex" -o "$WORK/smali"

echo "== applying the patches"
for p in "$DIR"/patches/*.py; do
    python3 "$p" "$WORK/smali"
done

echo "== reassembling"
"$JAVA" -Xmx3g -jar "$SMALI_DIR/smali.jar" a "$WORK/smali" -o "$WORK/classes-new.dex"

echo "== rebuilding the apk"
python3 - "$SRC" "$WORK/classes-new.dex" "$WORK/patched.apk" <<'PY'
import sys, zipfile
src, newdex, dst = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(newdex, "rb").read()
zin, zout = zipfile.ZipFile(src), zipfile.ZipFile(dst, "w")
for item in zin.infolist():
    # the old signatures are useless: the APK is re-signed by the build system
    if item.filename.startswith("META-INF/") and \
            item.filename.split("/")[-1].endswith((".RSA", ".SF", ".MF", ".DSA", ".EC")):
        continue
    info = zipfile.ZipInfo(item.filename, date_time=item.date_time)
    # the compression method has to be preserved: classes.dex and resources.arsc
    # must stay STORED, otherwise Android rejects the APK
    info.compress_type = item.compress_type
    info.external_attr = item.external_attr
    info.create_system = item.create_system
    zout.writestr(info, data if item.filename == "classes.dex" else zin.read(item.filename))
zout.close()
PY

echo "== aligning"
"$ZIPALIGN" -f -p 4 "$WORK/patched.apk" "$OUT"

echo
echo "done: $OUT"
echo "rebuild and reflash, then see docs/bringup/volte-stato-esperimento.md for activation."
