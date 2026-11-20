#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Puts back MediaTek's own test for whether the platform does video calls.

TrebleDroid's build answers false unconditionally, which is right on a GSI:
there is no vtservice there. Here there is one, and with the answer false
ImsVTProvider never loads libmtk_vt_wrapper.so, yet still calls into it when
a call ends -- every IMS call then took the service down with
UnsatisfiedLinkError on nFinalization.

The stock body, restored: video calls are on when persist.vendor.vilte_support
or persist.vendor.viwifi_support is "1". rootdir/etc/init/s88pro-vt.rc decides
those.

Usage: 06-video-call-platform-check.py <smali-dir>
"""
import io
import os
import re
import sys

d = sys.argv[1]
p = os.path.join(d, "com/mediatek/ims/internal/ImsVTProviderUtil.smali")
s = io.open(p, encoding="utf-8").read()

old = re.compile(r"\.method public static isVideoCallOnByPlatform\(\)Z\n"
                 r"    \.registers 1\n\n"
                 r"(    \.line \d+\n)?"
                 r"    const/4 v0, 0x0\n\n"
                 r"    return v0\n"
                 r"\.end method")

new = """.method public static isVideoCallOnByPlatform()Z
    .registers 3

    # MediaTek's own test, which TrebleDroid's build replaces with false.
    const-string v0, "0"

    const-string v1, "persist.vendor.vilte_support"

    invoke-static {v1, v0}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v1

    const-string v2, "1"

    invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v1

    if-nez v1, :on

    const-string v1, "persist.vendor.viwifi_support"

    invoke-static {v1, v0}, Landroid/os/SystemProperties;->get(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;

    move-result-object v0

    invoke-virtual {v0, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z

    move-result v0

    return v0

    :on
    const/4 v0, 0x1

    return v0
.end method"""

s, n = old.subn(lambda m: new, s)
if n != 1:
    sys.exit("06-video-call-platform-check: expected 1 match, found %d -- this is not the expected APK" % n)

io.open(p, "w", encoding="utf-8").write(s)
print("06-video-call-platform-check: applied")
