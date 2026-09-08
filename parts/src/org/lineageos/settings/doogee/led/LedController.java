/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.led;

import org.lineageos.settings.doogee.utils.FileUtils;

/**
 * Comanda la striscia di LED RGB sul retro della scocca.
 *
 * Il controller è un Awinic aw22xxx, esposto in /sys/class/leds/aw22xxx_led/.
 * Gli effetti non si programmano colore per colore: il driver carica un file di
 * firmware dal vendor (/vendor/firmware/) e lo esegue. La sequenza è quella del
 * firmware di fabbrica, dove il LED è gestito dentro BatteryService (che lo
 * chiama "marquee"):
 *
 *   hwen   = 1                 alimenta il controller
 *   effect = numero effetto    sceglie quale firmware caricare
 *   cfg    = 1                 lo applica
 *
 * Due dettagli, entrambi verificati sul device, che è facile sbagliare:
 *
 * 1. I valori vanno scritti senza andare a capo. Il "\n" di echo fa ricadere il
 *    driver sullo zero, cioè spegne.
 *
 * 2. Il nodo effect accetta **una sola cifra decimale**: gli indici da 10 in su
 *    vengono rifiutati e azzerati. Si può verificare rileggendo il nodo dopo la
 *    scrittura. Restano quindi fuori portata charging.bin (0xa),
 *    full_charged.bin (0xb) e short_message_notice.bin (0xd), che pure esistono
 *    in /vendor/firmware. Non è una nostra mancanza: il BatteryService di
 *    fabbrica scrive proprio "10" e "11" per la ricarica, valori che questo
 *    driver rifiuta, quindi quegli effetti non funzionavano neanche nella ROM
 *    originale. Qui si usano gli effetti raggiungibili.
 */
public final class LedController {

    private static final String BASE = "/sys/class/leds/aw22xxx_led/";
    private static final String NODE_HWEN = BASE + "hwen";
    private static final String NODE_EFFECT = BASE + "effect";
    private static final String NODE_CFG = BASE + "cfg";

    // Effetti raggiungibili, come li elenca il nodo cfg del driver.
    public static final int EFFECT_OFF = 0;
    public static final int EFFECT_ON = 1;
    public static final int EFFECT_BREATH = 2;
    public static final int EFFECT_COLLISION = 3;
    public static final int EFFECT_SKYLINE = 4;
    public static final int EFFECT_FLOWER = 5;
    public static final int EFFECT_AUDIO_SKYLINE = 6;
    public static final int EFFECT_AUDIO_FLOWER = 7;
    public static final int EFFECT_MUSIC_SYNC = 8;
    public static final int EFFECT_CALL_REMINDER = 9;

    private static int sCurrentEffect = -1;

    private LedController() {
    }

    public static boolean isSupported() {
        return FileUtils.isAccessible(NODE_CFG);
    }

    /** Esegue l'effetto indicato, se non è già quello in corso. */
    public static synchronized void setEffect(int effect) {
        if (effect == sCurrentEffect) {
            return;
        }
        sCurrentEffect = effect;

        if (effect == EFFECT_OFF) {
            FileUtils.writeLine(NODE_HWEN, 0);
            FileUtils.writeLine(NODE_EFFECT, 0);
            FileUtils.writeLine(NODE_CFG, 0);
            return;
        }

        FileUtils.writeLine(NODE_HWEN, 1);
        FileUtils.writeLine(NODE_EFFECT, effect);
        FileUtils.writeLine(NODE_CFG, 1);
    }

    public static void turnOff() {
        setEffect(EFFECT_OFF);
    }
}
