#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Removes the WFO (VoWiFi) service start-up from the ImsService constructor.

Why: ImsService.<init> calls startWfoService(), which ends up in
WifiPdnHandler, which uses WifiManager.registerStaStateCallback() -- a method
MediaTek added to the framework and that AOSP does not have. Providing a stub
for the StaStateCallback class is not enough: the method on WifiManager would
still be missing.

VoWiFi is therefore left out. The initialisation of mTempDisableWFC is kept,
though, since it is used elsewhere and its absence would cause an NPE.

Usage: 01-disable-wfo.py <smali-dir>
"""
import io, os, sys

d = sys.argv[1]
p = os.path.join(d, "com/mediatek/ims/ImsService.smali")
s = io.open(p, encoding="utf-8").read()

old = """    .line 691
    iget-object v0, p0, Lcom/mediatek/ims/ImsService;->mContext:Landroid/content/Context;

    invoke-static {v0}, Lcom/mediatek/wfo/impl/WfoService;->getInstance(Landroid/content/Context;)Lcom/mediatek/wfo/impl/WfoService;

    move-result-object v0

    invoke-virtual {v0}, Lcom/mediatek/wfo/impl/WfoService;->makeWfoService()V

    .line 692
    return-void"""

new = """    # WFO (VoWiFi) disabled: WifiPdnHandler uses WifiManager.registerStaStateCallback(),
    # a method MediaTek added to the framework and that AOSP does not have.
    .line 692
    return-void"""

if s.count(old) != 1:
    sys.exit("01-disable-wfo: expected 1 match, found %d -- this is not the expected APK"
             % s.count(old))

io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("01-disable-wfo: applied")
