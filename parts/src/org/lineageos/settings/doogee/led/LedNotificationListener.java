/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.led;

import android.content.Intent;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;

/**
 * Dice al LedService se ci sono notifiche in sospeso.
 *
 * Le notifiche continuative (musica in riproduzione, VPN attiva, e simili) non
 * contano: il LED segnala quello che l'utente non ha ancora visto.
 */
public class LedNotificationListener extends NotificationListenerService {

    @Override
    public void onListenerConnected() {
        notifyState();
    }

    @Override
    public void onNotificationPosted(StatusBarNotification sbn) {
        notifyState();
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification sbn) {
        notifyState();
    }

    private void notifyState() {
        boolean hasNotifications = false;
        final StatusBarNotification[] active = getActiveNotifications();
        if (active != null) {
            for (StatusBarNotification sbn : active) {
                if (!sbn.isOngoing() && sbn.isClearable()) {
                    hasNotifications = true;
                    break;
                }
            }
        }

        final Intent intent = new Intent(LedService.ACTION_NOTIFICATIONS_CHANGED);
        intent.setPackage(getPackageName());
        intent.putExtra(LedService.EXTRA_HAS_NOTIFICATIONS, hasNotifications);
        sendBroadcast(intent);
    }
}
