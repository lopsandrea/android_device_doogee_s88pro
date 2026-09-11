#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Device-specific additions to the OTA package, for s88pro.
#
# The build calls these hooks from build/make/tools/releasetools/non_ab_ota.py
# (FullOTA_Assertions at line 167, FullOTA_InstallEnd at line 288) once
# TARGET_RELEASETOOLS_EXTENSIONS points at this directory. They exist because
# two things this device needs cannot be expressed in BoardConfig.mk.

import common

# The stock vendor this tree was built against.
#
# Read from the phone with `getprop`, not copied from a spec sheet:
#   ro.vendor.build.fingerprint          DOOGEE/S88Pro_EEA/S88Pro:10/
#                                        QP1A.190711.020/1592876742:user/release-keys
#   ro.vendor.build.version.incremental  1592876742
VENDOR_FINGERPRINT = ("DOOGEE/S88Pro_EEA/S88Pro:10/QP1A.190711.020/"
                      "1592876742:user/release-keys")
VENDOR_INCREMENTAL = "1592876742"

RECOVERY_PARTITION = "/dev/block/platform/bootdevice/by-name/recovery"


def FullOTA_Assertions(info):
    """Refuse to install on a phone running a different stock firmware.

    The LineageOS charter asks a non-A/B device that relies on an OEM vendor
    partition to assert the vendor image version at flash time, and this device
    does rely on one: BOARD_PREBUILT_VENDORIMAGE ships the stock vendor as it
    is, and the whole tree -- the HALs it talks to, the SELinux policy it
    inherits, the firmware the modem loads -- is built against that one.

    On a phone carrying a different DOOGEE build the package would install and
    then fail somewhere far from here, with nothing to connect the two. Better
    to stop while there is still something to read.

    The test accepts either the full fingerprint or the incremental alone: a
    reflashed phone sometimes keeps the build number and loses the rest.
    """
    info.script.AppendExtra(
        'ifelse(\n'
        '  getprop("ro.vendor.build.fingerprint") == "%s" ||\n'
        '  getprop("ro.vendor.build.version.incremental") == "%s",\n'
        '  ui_print("Stock vendor %s: ok"),\n'
        '  abort("E3005: This package needs the stock DOOGEE vendor %s. '
        'This phone has \\"" + getprop("ro.vendor.build.fingerprint") + '
        '"\\". Flash the stock firmware first: the HALs, the SELinux policy '
        'and the modem firmware all come from it.")\n'
        ');' % (VENDOR_FINGERPRINT, VENDOR_INCREMENTAL,
                VENDOR_INCREMENTAL, VENDOR_INCREMENTAL))


def FullOTA_InstallEnd(info):
    """Write recovery.img, which otherwise travels in the package unused.

    non_ab_ota.py puts recovery.img in every package (line 197) but only writes
    it for two-step packages (line 211, inside `if OPTIONS.two_step`). The way
    AOSP installs it normally is install-recovery.sh, which lands in
    /vendor/bin -- and with BOARD_PREBUILT_VENDORIMAGE the build installs
    nothing into /vendor, so that road is closed here.

    Without this the charter requirement stands unmet in the plainest way:
    "LineageOS 18.1+ maintainers MUST ship LineageOS Recovery as the default
    solution", and whoever updated would keep whatever recovery they had.

    It is written exactly like boot.img, which the generated script already
    handles two lines above.
    """
    info.script.Print("Installing LineageOS Recovery...")
    info.script.AppendExtra(
        'package_extract_file("recovery.img", "%s");' % RECOVERY_PARTITION)
