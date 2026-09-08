#!/system/bin/sh
#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# Boost EAS per le app in primo piano. Il perche' e i numeri stanno nel file
# init che avvia questo script: rootdir/etc/init/s88pro-schedtune.rc
#
# L'attesa non e' un vezzo: applicati subito dopo sys.boot_completed i valori
# non attecchiscono -- prefer_idle resta, boost torna a zero -- mentre piu'
# tardi restano. Qualcosa nell'ultima fase dell'avvio li rimette a posto;
# passata quella, nessuno li tocca piu'.
#
# Quanto piu' tardi pero' dipende dalla versione: su Android 12 bastavano
# cinque secondi, su Android 13 no (il servizio scriveva 10 e qualcosa lo
# riportava a zero). Invece di indovinare un'attesa piu' lunga, si riapplica
# finche' il valore non tiene: si esce al primo giro in cui e' rimasto.

sleep 5

# Le app che l'utente sta guardando: frequenza piu' alta e preferenza per i
# core liberi. Sono i valori che AOSP usava fino ad Android 11.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    echo 10 > /dev/stune/top-app/schedtune.boost
    echo 1  > /dev/stune/top-app/schedtune.prefer_idle
    sleep 5
    [ "$(cat /dev/stune/top-app/schedtune.boost)" = "10" ] && break
done

# Il resto in primo piano: nessun boost, ma comunque core liberi. Alzare anche
# questo non serve, SystemUI sta gia' in top-app.
echo 0 > /dev/stune/foreground/schedtune.boost
echo 1 > /dev/stune/foreground/schedtune.prefer_idle

echo 0 > /dev/stune/rt/schedtune.boost
echo 1 > /dev/stune/rt/schedtune.prefer_idle

log -t s88pro-schedtune "top-app boost=$(cat /dev/stune/top-app/schedtune.boost) prefer_idle=$(cat /dev/stune/top-app/schedtune.prefer_idle)"
