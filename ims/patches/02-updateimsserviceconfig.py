#!/usr/bin/env python3
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
"""Adatta la chiamata a ImsManager.updateImsServiceConfig() alla firma di Android 12.

In Android 10 era statico e prendeva (Context, int phoneId, boolean force); in
Android 12 e' un metodo di istanza senza parametri. Il flag "force" non ha piu'
un corrispondente: la nuova implementazione rivaluta comunque le capability.

Si patcha la chiamata dentro l'APK e NON il framework. ImsManager sta in
ims-common.jar, che e' nel bootclasspath: sostituire quel jar rompe i checksum
della boot image precompilata e il telefono non si avvia piu' (recupero solo da
TWRP). Vedi docs/bringup/volte-stato-esperimento.md

Uso: 02-updateimsserviceconfig.py <dir-smali>
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

# .registers passa da 4 a 5 per avere v0 come registro locale: i parametri
# restano raggiungibili come pN, che smali rimappa da solo.
new = """.method public updateImsServiceConfig(Landroid/content/Context;IZ)V
    .registers 5
    .param p1, "context"    # Landroid/content/Context;
    .param p2, "phoneId"    # I
    .param p3, "force"    # Z

    # Android 12: updateImsServiceConfig() e' un metodo di istanza senza parametri.
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
    sys.exit("02-updateimsserviceconfig: atteso 1 riscontro, trovati %d -- l'APK non e' quello previsto"
             % s.count(old))

io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("02-updateimsserviceconfig: applicata")
