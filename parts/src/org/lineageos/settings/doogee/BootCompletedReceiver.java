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

/** Avvia il servizio del LED a ogni accensione. */
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
     * Concede a sé stessi l'accesso alle notifiche.
     *
     * Serve al LED per sapere se c'è qualcosa da leggere. È un permesso che di
     * norma concede l'utente dalle impostazioni, ma questa è un'app di sistema
     * del device: chiederlo avrebbe il solo effetto di far apparire il LED
     * "rotto" finché qualcuno non trova la voce giusta nel menù.
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
