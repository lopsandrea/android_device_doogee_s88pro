#!/bin/bash
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Prepares ImsService.apk, MediaTek's ImsService, for VoLTE.
#
# The starting point is not the stock ROM's copy but TrebleDroid's: the build of
# MediaTek's ImsService for Android 10 vendors that Phh Treble Settings installs
# on GSIs running on a "MediaTek Q" vendor, that is one registering
# vendor.mediatek.hardware.mtkradioex@1.x with imsSlotN instances, as this phone
# does:
#
#   https://treble.phh.me/stable/ims-mtk-q.apk
#
# Unlike the stock copy it does not lean on MediaTek's framework jars, nor on
# framework methods AOSP never had. Android 17 still lacks a few things it
# calls, and the scripts in patches/ deal with those, each explaining why. The
# dex is disassembled, patched and reassembled, and the APK aligned.
#
# Signing is left to the build system (Android.mk declares
# LOCAL_CERTIFICATE := platform): the APK shares android.uid.phone with
# com.android.phone, so it has to carry our platform signature.
#
# Usage:
#   ./prepare-imsservice.sh /path/to/ims-mtk-q.apk
#
# The result is ImsService.apk in this directory, which device.mk installs if
# it finds it. Without it, the build carries on without VoLTE.

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:?the path to ims-mtk-q.apk is required}"
OUT="$DIR/ImsService.apk"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The file the patches were written against: any other one has to be looked at
# before patching it.
SHA256=cdba840a6192d113d5808392f282b6f8d6d02f0da071a1af4990ab1d1e0d24c3

: "${ANDROID_BUILD_TOP:?run first: source build/envsetup.sh && lunch lineage_s88pro-cp2a-userdebug}"

JAVA="$(ls -d "$ANDROID_BUILD_TOP"/prebuilts/jdk/jdk*/linux-x86 | sort -V | tail -1)/bin/java"
SMALI_DIR="$ANDROID_BUILD_TOP/prebuilts/extract-tools/common/smali"
ZIPALIGN="$ANDROID_BUILD_TOP/prebuilts/build-tools/linux-x86/bin/zipalign"

echo "== checking $SRC"
echo "$SHA256  $SRC" | sha256sum -c --quiet - || {
    echo "this is not the ims-mtk-q.apk the patches were written for"; exit 1; }

echo "== extracting the dex"
unzip -o -q "$SRC" "classes*.dex" -d "$WORK"
[ -f "$WORK/classes2.dex" ] && { echo "expected a single dex, this APK has more than one"; exit 1; }

echo "== disassembling"
"$JAVA" -Xmx3g -jar "$SMALI_DIR/baksmali.jar" d "$WORK/classes.dex" -o "$WORK/smali"

echo "== compiling the gate"
# S88ViLteGate (gate/, see patches/07) is compiled against two stubs standing
# in for the APK's classes, and only the gate itself goes into the smali tree.
JDK_BIN="$(dirname "$JAVA")"
ANDROID_JAR="$ANDROID_BUILD_TOP/prebuilts/sdk/current/public/android.jar"
mkdir -p "$WORK/gate/classes" "$WORK/gate/dex"
"$JDK_BIN/javac" -source 11 -target 11 -nowarn -cp "$ANDROID_JAR" -d "$WORK/gate/classes" \
    $(find "$DIR/gate" -name "*.java")
"$JAVA" -cp "$ANDROID_BUILD_TOP/prebuilts/r8/r8.jar" com.android.tools.r8.D8 --release \
    --min-api 29 --lib "$ANDROID_JAR" --classpath "$WORK/gate/classes" \
    --output "$WORK/gate/dex" "$WORK/gate/classes/com/mediatek/ims/config/internal/S88ViLteGate.class"
"$JAVA" -jar "$SMALI_DIR/baksmali.jar" d "$WORK/gate/dex/classes.dex" -o "$WORK/smali"

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
