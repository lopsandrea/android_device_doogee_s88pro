/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.power;

import org.lineageos.settings.doogee.utils.FileUtils;

/**
 * Reverse charging: the phone powers another device resting on its back.
 *
 * The control lives in the sysfs group of the MT5725 wireless charging chip.
 * The state is read from the same node, which answers "reverse_charger en : 0"
 * or "... : 1".
 *
 * The "online" node under /sys/class/power_supply/rvs/ is not used: it is read
 * only, and with SELinux in Enforcing it is also unreachable, because
 * domain.te:1316 forbids platform domains from reading sysfs_batteryinfo files
 * and points at the health HAL -- which, however, exposes the standard
 * power_supply nodes, not a vendor "rvs".
 *
 * The control node, on the other hand, can be written, but only since it got a
 * type of its own (sysfs_rvs, see sepolicy/system_ext/private/genfs_contexts):
 * as generic sysfs nobody could touch it, not even init.
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
        final String state = FileUtils.readLine(NODE);
        return state != null && state.trim().endsWith("1");
    }
}
