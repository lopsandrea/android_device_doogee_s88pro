#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Points the calls Android 17 no longer resolves at what it has instead.

- SubscriptionManager.getSimStateForSlotIndex(int) moved to TelephonyManager,
  same signature and still static. ImsService$MyHandler calls it on every SIM
  state change.

- RIL.arrayListToPrimitiveArray(ArrayList<Byte>) is gone. ImsRadioIndication
  uses it to unpack SMS PDUs received over IMS; the same five lines are added
  to the APK as com.mediatek.ims.ril.S88Compat and the calls go there.

- StorageManager.inCryptKeeperBounce() is gone with CryptKeeper itself (file
  based encryption since Android 10 never "bounces"). The two Wi-Fi calling
  handlers ask it whenever Wi-Fi changes state; it is replaced by false.

Every substitution must match the expected number of times, or the script
stops: a different APK needs looking at, not a blind rewrite.

Usage: 04-removed-framework-calls.py <smali-dir>
"""
import io
import os
import re
import sys

d = sys.argv[1]


def patch(rel, subs):
    p = os.path.join(d, rel)
    s = io.open(p, encoding="utf-8").read()
    for pattern, repl, count in subs:
        s, n = re.subn(pattern, repl, s)
        if n != count:
            sys.exit(f"04-removed-framework-calls: {rel}: expected {count} match(es) of "
                     f"{pattern!r}, found {n} -- this is not the expected APK")
    io.open(p, "w", encoding="utf-8").write(s)


patch("com/mediatek/ims/ImsService$MyHandler.smali", [
    (re.escape("Landroid/telephony/SubscriptionManager;->getSimStateForSlotIndex(I)I"),
     "Landroid/telephony/TelephonyManager;->getSimStateForSlotIndex(I)I", 1),
])

patch("com/mediatek/ims/ril/ImsRadioIndication.smali", [
    (re.escape("Lcom/android/internal/telephony/RIL;->arrayListToPrimitiveArray(Ljava/util/ArrayList;)[B"),
     "Lcom/mediatek/ims/ril/S88Compat;->arrayListToPrimitiveArray(Ljava/util/ArrayList;)[B", 2),
])

CRYPT = (r"invoke-static \{\}, Landroid/os/storage/StorageManager;->inCryptKeeperBounce\(\)Z\n"
         r"\n(\s*)move-result (v\d+)")
for rel in ("com/mediatek/wfo/impl/WfcHandler.smali",
            "com/mediatek/wfo/impl/WifiPdnHandler.smali"):
    p = os.path.join(d, rel)
    n = io.open(p, encoding="utf-8").read().count("inCryptKeeperBounce()Z")
    patch(rel, [(CRYPT, r"const/4 \2, 0x0  # inCryptKeeperBounce(): always false since Android 10", n)])

helper = os.path.join(d, "com/mediatek/ims/ril/S88Compat.smali")
io.open(helper, "w", encoding="utf-8").write(""".class public final Lcom/mediatek/ims/ril/S88Compat;
.super Ljava/lang/Object;
.source "S88Compat.java"


# RIL.arrayListToPrimitiveArray(), which Android 17 removed.
.method public static arrayListToPrimitiveArray(Ljava/util/ArrayList;)[B
    .registers 5

    invoke-virtual {p0}, Ljava/util/ArrayList;->size()I

    move-result v0

    new-array v1, v0, [B

    const/4 v2, 0x0

    :loop
    if-ge v2, v0, :done

    invoke-virtual {p0, v2}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;

    move-result-object v3

    check-cast v3, Ljava/lang/Byte;

    invoke-virtual {v3}, Ljava/lang/Byte;->byteValue()B

    move-result v3

    aput-byte v3, v1, v2

    add-int/lit8 v2, v2, 0x1

    goto :loop

    :done
    return-object v1
.end method
""")
print("04-removed-framework-calls: applied")
