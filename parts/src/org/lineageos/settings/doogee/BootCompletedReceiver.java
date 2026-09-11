/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee;

import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;
import android.text.TextUtils;

import org.lineageos.settings.doogee.led.LedNotificationListener;
import org.lineageos.settings.doogee.led.LedService;

/** Starts the LED service on every boot. */
public class BootCompletedReceiver extends BroadcastReceiver {

    private static final String SETTING_ENABLED_LISTENERS = "enabled_notification_listeners";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            return;
        }
        enableNotificationListener(context);
        context.startService(new Intent(context, LedService.class));
    }

    /**
     * Grants itself access to notifications.
     *
     * The LED needs it to know whether there is anything to read. It is a
     * permission the user normally grants from settings, but this is a device
     * system app: asking would only make the LED look "broken" until someone
     * finds the right entry in the menu.
     */
    private void enableNotificationListener(Context context) {
        final String component = new ComponentName(context, LedNotificationListener.class)
                .flattenToString();
        final String current = Settings.Secure.getString(
                context.getContentResolver(), SETTING_ENABLED_LISTENERS);

        if (current != null && current.contains(component)) {
            return;
        }

        final String updated = TextUtils.isEmpty(current)
                ? component
                : current + ":" + component;
        Settings.Secure.putString(
                context.getContentResolver(), SETTING_ENABLED_LISTENERS, updated);
    }
}
