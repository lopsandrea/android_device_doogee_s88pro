#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Adds a do-nothing com.android.internal.telephony.metrics.TelephonyMetrics.

ImsRILAdapter and MwiRIL take TelephonyMetrics.getInstance() in their
constructors and report a few RIL events to it. Android 17 no longer has the
class, so the service dies on start-up with NoClassDefFoundError, before the
framework can even query its features.

The boot classpath does not define the class, so the copy added here is the one
the app's class loader finds; the MediaTek code is left untouched. Only the
methods the APK calls are provided, and they discard their arguments: the
metrics they fed are gone from the platform anyway.

Usage: 03-telephony-metrics-stub.py <smali-dir>
"""
import io
import os
import sys

d = sys.argv[1]
p = os.path.join(d, "com/android/internal/telephony/metrics/TelephonyMetrics.smali")
if os.path.exists(p):
    sys.exit("03-telephony-metrics-stub: the APK already has TelephonyMetrics -- not the expected APK")

T = "Lcom/android/internal/telephony/metrics/TelephonyMetrics;"

# name and descriptor of every method the APK calls, with the register count
# each needs (this + parameters, all of them one register wide)
METHODS = [
    ("writeOnRilSolicitedResponse", "(IIIILjava/lang/Object;)V", 6),
    ("writeOnRilTimeoutResponse", "(III)V", 4),
    ("writeRilAnswer", "(II)V", 3),
    ("writeRilSendSms", "(IIII)V", 5),
]

out = [f""".class public L{T[1:-1]};
.super Ljava/lang/Object;
.source "TelephonyMetrics.java"


.field private static final sInstance:{T}


.method static constructor <clinit>()V
    .registers 1

    new-instance v0, {T}

    invoke-direct {{v0}}, {T}-><init>()V

    sput-object v0, {T}->sInstance:{T}

    return-void
.end method

.method private constructor <init>()V
    .registers 1

    invoke-direct {{p0}}, Ljava/lang/Object;-><init>()V

    return-void
.end method

.method public static getInstance(){T}
    .registers 1

    sget-object v0, {T}->sInstance:{T}

    return-object v0
.end method
"""]
for name, desc, regs in METHODS:
    out.append(f"""
.method public {name}{desc}
    .registers {regs}

    return-void
.end method
""")

os.makedirs(os.path.dirname(p), exist_ok=True)
io.open(p, "w", encoding="utf-8").write("".join(out))
print("03-telephony-metrics-stub: applied")
