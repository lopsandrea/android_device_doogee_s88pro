#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Extracts the proprietary blobs this tree needs.
#
# With no argument it reads them from a phone over adb, which is what the
# charter asks for -- the script has to reproduce the blobs "from an existing
# LineageOS installation", so that anyone with the phone can rebuild the tree
# without our images. A directory or an image also works, and that is how it
# gets run here:
#
#   ./extract-files.sh                     from the phone over adb
#   ./extract-files.sh /mnt/stock          from the stock images, mounted
#
# There are 24 blobs, all of them going into system: the MediaTek framework
# .jars and the libraries that go with them, plus libfmjni, which in the stock
# ROM lives in product. Everything the vendor partition holds is NOT here --
# that image is shipped whole (BOARD_PREBUILT_VENDORIMAGE).

set -e

DEVICE=s88pro
VENDOR=doogee

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
