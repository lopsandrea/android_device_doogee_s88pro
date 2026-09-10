#!/usr/bin/env bash
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Estrae i blob proprietari dalle immagini stock montate in /mnt/stock.
#
# Perche' da immagini e non da device via adb, come fa lo script standard di
# LineageOS: le immagini sono quelle estratte dalla super del telefono in
# Fase 2 e corrispondono al firmware di fabbrica, mentre il device e' stato
# modificato piu' volte. La sorgente e' quindi piu' affidabile e ripetibile.
#
# Nota sui percorsi: system.img e' system-as-root, quindi i file stanno in
# /mnt/stock/system/system/... mentre nel device tree il prefisso e' "system/".
set -euo pipefail

DEVICE=s88pro
VENDOR=doogee
SRC_SYSTEM=/mnt/stock/system
SRC_VENDOR=/mnt/stock/vendor
SRC_PRODUCT=/mnt/stock/product

# La partizione product non e' montata (montarla vuole root) ma la sua immagine
# c'e' fra gli artefatti, e debugfs la legge senza privilegi. Serve per
# libfmjni.so, che nella ROM di fabbrica sta in product/lib* e non in system.
PRODUCT_IMG=/mnt/s88pro/gsi-work/product.img
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/../../../vendor/$VENDOR/$DEVICE/proprietary"

[ -d "$SRC_SYSTEM/system" ] || { echo "system.img non montata in $SRC_SYSTEM" >&2; exit 1; }

mkdir -p "$DEST"
copied=0
missing=0

while read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  f="${line#-}"

  # Sintassi "sorgente:destinazione", come nell'extract_utils di LineageOS:
  # serve quando un blob va installato con un altro nome. Qui capita per
  # ims-common.jar, che diventa mtk-ims-compat.jar per non sovrapporsi
  # all'ims-common.jar che compiliamo noi e che serve al framework.
  case "$f" in
    *:*) dst="${f#*:}"; f="${f%%:*}" ;;
    *)   dst="$f" ;;
  esac

  # I file di product si prendono dall'immagine con debugfs, se la partizione
  # non e' montata: dentro l'immagine il percorso non ha il prefisso "product/".
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
          echo "MANCA: $f  (non estratto da $PRODUCT_IMG)" >&2
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
    echo "MANCA: $f  (cercato in $src)" >&2
    missing=$((missing+1))
  fi
done < "$HERE/proprietary-files.txt"

echo "blob copiati: $copied, mancanti: $missing"
echo "destinazione: $DEST"
[ "$missing" -eq 0 ] || exit 1
