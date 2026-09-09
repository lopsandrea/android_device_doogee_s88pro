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
 * Il comando sta nel gruppo sysfs del chip di ricarica wireless MT5725. Lo
 * stato si legge dallo stesso nodo, che risponde "reverse_charger en : 0"
 * oppure "... : 1".
 *
 * Il nodo "online" sotto /sys/class/power_supply/rvs/ non si usa: e' di sola
 * lettura, e con SELinux in Enforcing e' anche irraggiungibile, perche'
 * domain.te:1316 vieta ai domini di piattaforma di leggere i file
 * sysfs_batteryinfo e rimanda alla health HAL -- che pero' espone i
 * power_supply standard, non un "rvs" del vendor.
 *
 * Il nodo di comando invece si scrive, ma solo da quando ha un tipo suo
 * (sysfs_rvs, vedi sepolicy/system_ext/private/genfs_contexts): come sysfs
 * generico non lo poteva toccare nessuno, nemmeno init.
 */
public final class ReverseChargingController {

    private static final String NODE =
            "/sys/devices/platform/11005000.i2c/i2c-6/6-002b/mt5725group/reverse_charger";

    private ReverseChargingController() {
    }

    public static boolean isSupported() {
        return FileUtils.isAccessible(NODE);
    }

    public static void setEnabled(boolean enabled) {
        FileUtils.writeLine(NODE, enabled ? 1 : 0);
    }

    public static boolean isEnabled() {
        final String stato = FileUtils.readLine(NODE);
        return stato != null && stato.trim().endsWith("1");
    }
}
