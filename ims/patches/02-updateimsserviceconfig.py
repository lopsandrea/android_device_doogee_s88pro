#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Adapts the ImsManager.updateImsServiceConfig() call to the Android 12 signature.

In Android 10 it was static and took (Context, int phoneId, boolean force); in
Android 12 it is an instance method with no parameters. The "force" flag has no
counterpart any more: the new implementation re-evaluates the capabilities
regardless.

The call is patched inside the APK and NOT in the framework. ImsManager lives
in ims-common.jar, which is on the bootclasspath: replacing that jar breaks the
checksums of the precompiled boot image and the phone no longer boots (recovery
only through TWRP). See docs/bringup/volte-stato-esperimento.md

Usage: 02-updateimsserviceconfig.py <smali-dir>
"""
import io, os, sys

d = sys.argv[1]
p = os.path.join(d, "com/mediatek/ims/plugin/impl/ImsManagerOemPluginBase.smali")
s = io.open(p, encoding="utf-8").read()

old = """.method public updateImsServiceConfig(Landroid/content/Context;IZ)V
    .registers 4
    .param p1, "context"    # Landroid/content/Context;
    .param p2, "phoneId"    # I
    .param p3, "force"    # Z

    .line 64
    invoke-static {p1, p2, p3}, Lcom/android/ims/ImsManager;->updateImsServiceConfig(Landroid/content/Context;IZ)V

    .line 65
    return-void
.end method"""

# .registers goes from 4 to 5 to get v0 as a local register: the parameters
# stay reachable as pN, which smali remaps by itself.
new = """.method public updateImsServiceConfig(Landroid/content/Context;IZ)V
    .registers 5
    .param p1, "context"    # Landroid/content/Context;
    .param p2, "phoneId"    # I
    .param p3, "force"    # Z

    # Android 12: updateImsServiceConfig() is an instance method with no parameters.
    .line 64
    invoke-static {p1, p2}, Lcom/android/ims/ImsManager;->getInstance(Landroid/content/Context;I)Lcom/android/ims/ImsManager;

    move-result-object v0

    if-eqz v0, :cond_ret

    invoke-virtual {v0}, Lcom/android/ims/ImsManager;->updateImsServiceConfig()V

    .line 65
    :cond_ret
    return-void
.end method"""

if s.count(old) != 1:
    sys.exit("02-updateimsserviceconfig: expected 1 match, found %d -- this is not the expected APK"
             % s.count(old))

io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("02-updateimsserviceconfig: applied")
