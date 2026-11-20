#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Hooks S88ViLteGate (ims/gate/) into ImsConfigImpl and ImsService.

With video over LTE in the configuration before a slot's IMS has started,
the modem never starts it: no IMS PDN, no registration, voice gone too. Added
to a registration that already exists, video is accepted. The gate holds the
framework's ViLTE request back until the slot registers; see the class for
the details. prepare-imsservice.sh compiles it into the smali tree before the
patches run.

Two calls go in:
  - first thing in ImsConfigImpl.setFeatureValue(), the value it is asked to
    apply goes through S88ViLteGate.filter();
  - first thing in ImsService.updateImsRegstration(), S88ViLteGate hears of
    each registration state.

Usage: 07-vilte-after-registration.py <smali-dir>
"""
import io
import os
import re
import sys

d = sys.argv[1]
GATE = "Lcom/mediatek/ims/config/internal/S88ViLteGate;"

if not os.path.exists(os.path.join(d, "com/mediatek/ims/config/internal/S88ViLteGate.smali")):
    sys.exit("07-vilte-after-registration: S88ViLteGate.smali missing -- run through prepare-imsservice.sh")


def hook(rel, method, code):
    p = os.path.join(d, rel)
    s = io.open(p, encoding="utf-8").read()
    # the method header, its .registers and its .param lines; the call goes
    # right after them, before the first instruction
    pattern = re.compile(r"(" + re.escape(method) + r"\n    \.registers \d+\n"
                         r"(?:    \.param [^\n]*\n)*)")
    s, n = pattern.subn(lambda m: m.group(1) + code, s)
    if n != 1:
        sys.exit(f"07-vilte-after-registration: {rel}: expected 1 match of {method}, found {n}")
    io.open(p, "w", encoding="utf-8").write(s)


# p3 is the value; v0 is free at this point, the method assigns it before use.
hook("com/mediatek/ims/config/internal/ImsConfigImpl.smali",
     ".method public setFeatureValue(IIILcom/android/ims/ImsConfigListener;)V",
     f"""
    # S88ViLteGate: ViLTE waits for IMS registration.
    iget v0, p0, Lcom/mediatek/ims/config/internal/ImsConfigImpl;->mPhoneId:I

    invoke-static {{p0, v0, p1, p2, p3}}, {GATE}->filter(Lcom/mediatek/ims/config/internal/ImsConfigImpl;IIII)I

    move-result p3
""")

hook("com/mediatek/ims/ImsService.smali",
     ".method private updateImsRegstration(IIILandroid/telephony/ims/ImsReasonInfo;)V",
     f"""
    # S88ViLteGate: ViLTE follows IMS registration.
    invoke-static {{p1, p2}}, {GATE}->onRegistrationState(II)V
""")

print("07-vilte-after-registration: applied")
