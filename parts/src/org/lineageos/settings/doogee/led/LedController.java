/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.led;

import org.lineageos.settings.doogee.utils.FileUtils;

/**
 * Drives the RGB LED strip on the back of the case.
 *
 * The controller is an Awinic aw22xxx, exposed at /sys/class/leds/aw22xxx_led/.
 * Effects are not programmed colour by colour: the driver loads a firmware file
 * from the vendor (/vendor/firmware/) and runs it. The sequence is the one from
 * the stock firmware, where the LED is handled inside BatteryService (which
 * calls it "marquee"):
 *
 *   hwen   = 1                 powers the controller
 *   effect = effect number     picks which firmware to load
 *   cfg    = 1                 applies it
 *
 * Two details, both verified on the device, that are easy to get wrong:
 *
 * 1. Values must be written without a trailing newline. The "\n" from echo makes
 *    the driver fall back to zero, that is, it turns the LED off.
 *
 * 2. The effect node accepts **a single decimal digit**: indexes from 10 upwards
 *    are rejected and zeroed. This can be checked by reading the node back after
 *    writing. So charging.bin (0xa), full_charged.bin (0xb) and
 *    short_message_notice.bin (0xd) stay out of reach, even though they do exist
 *    in /vendor/firmware. This is not a shortcoming of ours: the stock
 *    BatteryService writes exactly "10" and "11" for charging, values this
 *    driver rejects, so those effects did not work in the original ROM either.
 *    Here we use the effects that can be reached.
 */
public final class LedController {

    private static final String BASE = "/sys/class/leds/aw22xxx_led/";
    private static final String NODE_HWEN = BASE + "hwen";
    private static final String NODE_EFFECT = BASE + "effect";
    private static final String NODE_CFG = BASE + "cfg";

    // Reachable effects, as the driver's cfg node lists them.
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

    /** Runs the given effect, unless it is already the one playing. */
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
