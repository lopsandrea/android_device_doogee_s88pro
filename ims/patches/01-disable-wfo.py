#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Toglie l'avvio del servizio WFO (VoWiFi) dal costruttore di ImsService.

Perche': ImsService.<init> chiama startWfoService(), che finisce in
WifiPdnHandler, che usa WifiManager.registerStaStateCallback() -- un metodo che
MediaTek ha aggiunto al framework e che AOSP non ha. Non basta fornire uno stub
della classe StaStateCallback: mancherebbe comunque il metodo su WifiManager.

Il VoWiFi resta quindi fuori. Si conserva pero' l'inizializzazione di
mTempDisableWFC, che viene usata altrove e la cui assenza darebbe NPE.

Uso: 01-disable-wfo.py <dir-smali>
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

new = """    # WFO (VoWiFi) disattivato: WifiPdnHandler usa WifiManager.registerStaStateCallback(),
    # un metodo che MediaTek ha aggiunto al framework e che AOSP non ha.
    .line 692
    return-void"""

if s.count(old) != 1:
    sys.exit("01-disable-wfo: atteso 1 riscontro, trovati %d -- l'APK non e' quello previsto"
             % s.count(old))

io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("01-disable-wfo: applicata")
