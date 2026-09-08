#!/usr/bin/env bash
# Genera i makefile di vendor/doogee/s88pro a partire da proprietary-files.txt.
#
# Perche' non basta un PRODUCT_COPY_FILES generico: ne' gli APK ne' i file ELF
# possono essere copiati cosi'. Il build system rifiuta con
#   error: Prebuilt apk found in PRODUCT_COPY_FILES: ... use BUILD_PREBUILT instead!
# e per le librerie native con
#   FAILED: ...check-non-elf-file-timestamps.../lib64/libXXX.so.timestamp
# Entrambi vanno dichiarati come moduli in Android.mk.
#
# I file vengono quindi divisi per tipo:
#   .apk -> modulo BUILD_PREBUILT (APPS) + PRODUCT_PACKAGES
#   .so  -> modulo BUILD_PREBUILT (SHARED_LIBRARIES) + PRODUCT_PACKAGES
#   resto (.jar, .xml) -> PRODUCT_COPY_FILES
#
# Le righe possono avere la forma "sorgente:destinazione", come nell'extract_utils
# di LineageOS, per installare un blob con un altro nome. Qui conta solo la
# destinazione: extract-files.sh ha gia' copiato il file in proprietary/ con il
# nome finale.
set -euo pipefail

DEVICE=s88pro
VENDOR=doogee
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/proprietary-files.txt"
OUT="$HERE/../../../vendor/$VENDOR/$DEVICE"

mkdir -p "$OUT"

# --- Android.mk: moduli prebuilt per gli APK ---
{
  cat << 'HEADER'
# Generato da device/doogee/s88pro/setup-makefiles.sh — non modificare a mano.

LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),s88pro)

HEADER

  while read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    f="${line#-}"
    case "$f" in *:*) f="${f#*:}" ;; esac
    case "$f" in
      *.apk)
        name="$(basename "$f" .apk)"
        cat << MODULE
include \$(CLEAR_VARS)
LOCAL_MODULE := $name
LOCAL_MODULE_OWNER := $VENDOR
LOCAL_SRC_FILES := proprietary/$f
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := .apk
LOCAL_CERTIFICATE := platform
LOCAL_PRIVILEGED_MODULE := true
LOCAL_MODULE_TAGS := optional
LOCAL_DEX_PREOPT := false
include \$(BUILD_PREBUILT)

MODULE
        ;;
      *.so)
        name="$(basename "$f" .so)"
        case "$f" in *lib64*) bits=64 ;; *) bits=32 ;; esac

        # Una libreria presente in entrambe le architetture (lib e lib64) va
        # dichiarata una volta sola, con LOCAL_MULTILIB := both: due moduli con
        # lo stesso LOCAL_MODULE si sovrascriverebbero a vicenda. Il file a 32
        # bit viene quindi saltato se esiste anche la sua versione a 64.
        other="$(echo "$f" | sed 's#/lib64/#/lib/#')"
        if [ "$bits" = "32" ] && grep -qxF "$(echo "$f" | sed 's#/lib/#/lib64/#')" "$LIST"; then
          continue
        fi
        if [ "$bits" = "64" ] && grep -qxF "$other" "$LIST"; then
          cat << MODULE
include \$(CLEAR_VARS)
LOCAL_MODULE := $name
LOCAL_MODULE_OWNER := $VENDOR
LOCAL_SRC_FILES_64 := proprietary/$f
LOCAL_SRC_FILES_32 := proprietary/$other
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_SUFFIX := .so
LOCAL_MULTILIB := both
LOCAL_MODULE_TAGS := optional
LOCAL_STRIP_MODULE := false
LOCAL_CHECK_ELF_FILES := false
include \$(BUILD_PREBUILT)

MODULE
          continue
        fi

        cat << MODULE
include \$(CLEAR_VARS)
LOCAL_MODULE := $name
LOCAL_MODULE_OWNER := $VENDOR
LOCAL_SRC_FILES := proprietary/$f
LOCAL_MODULE_CLASS := SHARED_LIBRARIES
LOCAL_MODULE_SUFFIX := .so
LOCAL_MULTILIB := $bits
LOCAL_MODULE_TAGS := optional
LOCAL_STRIP_MODULE := false
LOCAL_CHECK_ELF_FILES := false
include \$(BUILD_PREBUILT)

MODULE
        ;;
    esac
  done < "$LIST"

  echo "endif"
} > "$OUT/Android.mk"

# --- s88pro-vendor.mk: copia dei file non-APK + pacchetti ---
{
  cat << 'HEADER'
# Generato da device/doogee/s88pro/setup-makefiles.sh — non modificare a mano.
#
# Blob proprietari MediaTek estratti da system.img stock: sono i componenti
# framework che alla GSI mancavano e senza i quali mtkfusionrild resta in
# loop sul socket rild-oem.

PRODUCT_COPY_FILES += \
HEADER

  while read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    f="${line#-}"
    case "$f" in *:*) f="${f#*:}" ;; esac
    case "$f" in
      *.apk|*.so) continue ;;
      *) echo "    vendor/$VENDOR/$DEVICE/proprietary/$f:\$(TARGET_COPY_OUT_SYSTEM)/${f#system/} \\" ;;
    esac
  done < "$LIST"

  echo ""
  echo ""
  echo "PRODUCT_PACKAGES += \\"
  # I nomi vanno deduplicati: una libreria presente sia in lib che in lib64
  # compare due volte nell'elenco ma è un modulo solo.
  {
    while read -r line; do
      case "$line" in ''|'#'*) continue ;; esac
      f="${line#-}"
      case "$f" in *:*) f="${f#*:}" ;; esac
      case "$f" in
        *.apk) basename "$f" .apk ;;
        *.so)  basename "$f" .so ;;
      esac
    done < "$LIST"
  } | sort -u | sed 's/^/    /; s/$/ \\/'
  echo ""
} > "$OUT/$DEVICE-vendor.mk"

echo "generati:"
echo "  $OUT/Android.mk"
echo "  $OUT/$DEVICE-vendor.mk"
