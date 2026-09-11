#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Generates vendor/doogee/s88pro from proprietary-files.txt.
#
# Everything here is written by tools/extract-utils. The version this replaced
# built the makefiles by hand, and had reason to: it was carrying the 1622
# files of the vendor partition, 947 of them libraries, and the routes
# extract-utils takes do not scale to that. They do not have to any more --
# the vendor partition is shipped whole as an image, and what is left is 24
# files that go into system.
#
# The stock vendor's symlinks went with that change and are not missed: they
# were created under TARGET_OUT_VENDOR, which BOARD_PREBUILT_VENDORIMAGE never
# packs, and the same symlinks already exist inside the stock image -- checked
# on the phone:
#   /vendor/lib64/hw/gatekeeper.mt6771.so -> gatekeeper.trustkernel.so
#   /vendor/lib64/hw/vulkan.mt6771.so     -> /vendor/lib64/egl/libGLES_mali.so

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

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}"

# Warning headers and guards
write_headers

write_makefiles "${MY_DIR}/proprietary-files.txt" true

# Finish
write_footers
