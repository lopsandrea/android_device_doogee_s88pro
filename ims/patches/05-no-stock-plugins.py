#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Keeps the service on its built-in plugins.

ExtensionFactory looks for MediaTek's extension, legacy and OEM plugin jars at
fixed paths in /system/framework and, when one is there, loads its classes
instead of the defaults inside the APK. This tree ships the stock copies of
those jars with the blobs, built against the stock framework: the extension
plugin's ImsCallPluginImpl calls MtkTelephonyManagerEx, which only the stock
framework had, and the service dies on start-up with ClassNotFoundException.

On a GSI the files do not exist and the APK runs on its defaults, which is how
TrebleDroid ships it. The paths are pointed somewhere that does not exist, so
that the same happens here whatever /system/framework holds.

Usage: 05-no-stock-plugins.py <smali-dir>
"""
import io
import os
import sys

d = sys.argv[1]
p = os.path.join(d, "com/mediatek/ims/plugin/ExtensionFactory.smali")
s = io.open(p, encoding="utf-8").read()

old = '"/system/framework/mediatek-ims-'
new = '"/nonexistent/mediatek-ims-'
# extension plugin, legacy component and OEM plugin, each named twice: in the
# constant field and where it is used
if s.count(old) != 6:
    sys.exit("05-no-stock-plugins: expected 6 matches, found %d -- this is not the expected APK"
             % s.count(old))

io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("05-no-stock-plugins: applied")
