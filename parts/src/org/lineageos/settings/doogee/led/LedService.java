/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.led;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.os.BatteryManager;
import android.os.IBinder;
import android.preference.PreferenceManager;
import android.telephony.PhoneStateListener;
import android.telephony.TelephonyManager;
import android.util.Log;

/**
 * Accende la striscia RGB posteriore in base a cosa sta facendo il telefono.
 *
 * Le priorità sono quelle del firmware di fabbrica: una chiamata in arrivo
 * conta più dello stato della batteria, che a sua volta conta più delle
 * notifiche. Il LED torna spento quando non c'è nulla da segnalare.
 */
public class LedService extends Service {

    private static final String TAG = "S88ProParts";

    public static final String PREF_LED_ENABLED = "led_enabled";
    public static final String PREF_LED_CHARGING = "led_charging";
    public static final String PREF_LED_NOTIFICATIONS = "led_notifications";
    public static final String PREF_LED_CALLS = "led_calls";

    /** Inviata dal listener delle notifiche quando cambia il numero di notifiche attive. */
    public static final String ACTION_NOTIFICATIONS_CHANGED =
            "org.lineageos.settings.doogee.NOTIFICATIONS_CHANGED";
    public static final String EXTRA_HAS_NOTIFICATIONS = "has_notifications";

    private SharedPreferences mPrefs;
    private TelephonyManager mTelephonyManager;

    private boolean mCharging;
    private boolean mFullyCharged;
    private boolean mHasNotifications;
    private boolean mRinging;

    private final BroadcastReceiver mReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            final String action = intent.getAction();
            if (Intent.ACTION_BATTERY_CHANGED.equals(action)) {
                final int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS,
                        BatteryManager.BATTERY_STATUS_UNKNOWN);
                mCharging = status == BatteryManager.BATTERY_STATUS_CHARGING;
                mFullyCharged = status == BatteryManager.BATTERY_STATUS_FULL;
            } else if (ACTION_NOTIFICATIONS_CHANGED.equals(action)) {
                mHasNotifications = intent.getBooleanExtra(EXTRA_HAS_NOTIFICATIONS, false);
            }
            updateLed();
        }
    };

    private final PhoneStateListener mPhoneStateListener = new PhoneStateListener() {
        @Override
        public void onCallStateChanged(int state, String phoneNumber) {
            mRinging = state == TelephonyManager.CALL_STATE_RINGING;
            updateLed();
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();

        if (!LedController.isSupported()) {
            Log.w(TAG, "Nessun LED aw22xxx su questo device, il servizio si ferma");
            stopSelf();
            return;
        }

        mPrefs = PreferenceManager.getDefaultSharedPreferences(this);

        final IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_BATTERY_CHANGED);
        filter.addAction(ACTION_NOTIFICATIONS_CHANGED);
        registerReceiver(mReceiver, filter);

        mTelephonyManager = getSystemService(TelephonyManager.class);
        if (mTelephonyManager != null) {
            mTelephonyManager.listen(mPhoneStateListener, PhoneStateListener.LISTEN_CALL_STATE);
        }
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        try {
            unregisterReceiver(mReceiver);
        } catch (IllegalArgumentException ignored) {
            // Il servizio può essersi fermato prima di registrarsi.
        }
        if (mTelephonyManager != null) {
            mTelephonyManager.listen(mPhoneStateListener, PhoneStateListener.LISTEN_NONE);
        }
        LedController.turnOff();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        updateLed();
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void updateLed() {
        if (mPrefs == null || !mPrefs.getBoolean(PREF_LED_ENABLED, true)) {
            LedController.turnOff();
            return;
        }

        // Gli effetti pensati per ricarica e SMS non sono raggiungibili su
        // questo driver (vedi LedController): al loro posto si usano quelli
        // disponibili che rendono meglio l'idea.
        if (mRinging && mPrefs.getBoolean(PREF_LED_CALLS, true)) {
            LedController.setEffect(LedController.EFFECT_CALL_REMINDER);
        } else if (mPrefs.getBoolean(PREF_LED_CHARGING, true) && mFullyCharged) {
            LedController.setEffect(LedController.EFFECT_ON);
        } else if (mPrefs.getBoolean(PREF_LED_CHARGING, true) && mCharging) {
            LedController.setEffect(LedController.EFFECT_BREATH);
        } else if (mHasNotifications && mPrefs.getBoolean(PREF_LED_NOTIFICATIONS, true)) {
            LedController.setEffect(LedController.EFFECT_COLLISION);
        } else {
            LedController.turnOff();
        }
    }
}
