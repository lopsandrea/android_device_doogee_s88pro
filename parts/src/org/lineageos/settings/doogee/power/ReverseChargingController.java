/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.power;

import org.lineageos.settings.doogee.utils.FileUtils;

/**
 * Ricarica inversa: il telefono alimenta un altro dispositivo appoggiato sul retro.
 *
 * Il comando sta nel gruppo sysfs del chip di ricarica wireless MT5725. Il nodo
 * "online" sotto /sys/class/power_supply/rvs/ non serve: è di sola lettura e
 * riporta soltanto lo stato.
 */
public final class ReverseChargingController {

    private static final String NODE =
            "/sys/devices/platform/11005000.i2c/i2c-6/6-002b/mt5725group/reverse_charger";

    private static final String STATUS = "/sys/class/power_supply/rvs/online";

    private ReverseChargingController() {
    }

    public static boolean isSupported() {
        return FileUtils.isAccessible(NODE);
    }

    public static void setEnabled(boolean enabled) {
        FileUtils.writeLine(NODE, enabled ? 1 : 0);
    }

    public static boolean isEnabled() {
        return "1".equals(FileUtils.readLine(STATUS));
    }
}
