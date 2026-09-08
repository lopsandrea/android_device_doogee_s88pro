#!/bin/bash
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Prepara ImsService.apk per VoLTE: decompila il dex della ROM di fabbrica,
# applica le patch in patches/, ricompila e allinea. La firma NON si fa qui:
# ci pensa il build system, perche' Android.mk dichiara LOCAL_CERTIFICATE :=
# platform. Serve la chiave di piattaforma perche' l'APK usa
# sharedUserId="android.uid.phone" e deve condividere lo UID con com.android.phone.
#
# Uso:
#   ./prepare-imsservice.sh /percorso/della/rom/stock/system/priv-app/ImsService/ImsService.apk
#
# Il risultato e' ImsService.apk in questa directory, che device.mk installa
# come priv-app se lo trova. Senza, la build prosegue senza VoLTE.
#
# Lo stato di questo lavoro -- cosa funziona e cosa no -- e' in
# docs/bringup/volte-stato-esperimento.md

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${1:?serve il percorso di ImsService.apk della ROM di fabbrica}"
OUT="$DIR/ImsService.apk"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

: "${ANDROID_BUILD_TOP:?esegui prima: source build/envsetup.sh && lunch lineage_s88pro-userdebug}"

JAVA="$ANDROID_BUILD_TOP/prebuilts/jdk/jdk11/linux-x86/bin/java"
SMALI_DIR="$ANDROID_BUILD_TOP/prebuilts/extract-tools/common/smali"
ZIPALIGN="$ANDROID_BUILD_TOP/out/soong/host/linux-x86/bin/zipalign"

echo "== estraggo il dex da $SRC"
unzip -o -q "$SRC" "classes*.dex" -d "$WORK"
[ -f "$WORK/classes2.dex" ] && { echo "atteso un solo dex, questo APK ne ha piu' di uno"; exit 1; }

echo "== decompilo"
"$JAVA" -Xmx3g -jar "$SMALI_DIR/baksmali.jar" d "$WORK/classes.dex" -o "$WORK/smali"

echo "== applico le patch"
for p in "$DIR"/patches/*.py; do
    python3 "$p" "$WORK/smali"
done

echo "== ricompilo"
"$JAVA" -Xmx3g -jar "$SMALI_DIR/smali.jar" a "$WORK/smali" -o "$WORK/classes-new.dex"

echo "== ricostruisco l'apk"
python3 - "$SRC" "$WORK/classes-new.dex" "$WORK/patched.apk" <<'PY'
import sys, zipfile
src, newdex, dst = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(newdex, "rb").read()
zin, zout = zipfile.ZipFile(src), zipfile.ZipFile(dst, "w")
for item in zin.infolist():
    # le vecchie firme non servono: l'APK viene rifirmato dal build system
    if item.filename.startswith("META-INF/") and \
            item.filename.split("/")[-1].endswith((".RSA", ".SF", ".MF", ".DSA", ".EC")):
        continue
    info = zipfile.ZipInfo(item.filename, date_time=item.date_time)
    # va preservato il metodo di compressione: classes.dex e resources.arsc
    # devono restare STORED, altrimenti Android rifiuta l'APK
    info.compress_type = item.compress_type
    info.external_attr = item.external_attr
    info.create_system = item.create_system
    zout.writestr(info, data if item.filename == "classes.dex" else zin.read(item.filename))
zout.close()
PY

echo "== allineo"
"$ZIPALIGN" -f -p 4 "$WORK/patched.apk" "$OUT"

echo
echo "fatto: $OUT"
echo "ricompila e riflasha, poi vedi docs/bringup/volte-stato-esperimento.md per l'attivazione."
