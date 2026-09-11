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
 * Lights the rear RGB strip according to what the phone is doing.
 *
 * The priorities are those of the stock firmware: an incoming call outranks
 * the battery state, which in turn outranks notifications. The LED goes back
 * to off when there is nothing to signal.
 */
public class LedService extends Service {

    private static final String TAG = "S88ProParts";

    public static final String PREF_LED_ENABLED = "led_enabled";
    public static final String PREF_LED_CHARGING = "led_charging";
    public static final String PREF_LED_NOTIFICATIONS = "led_notifications";
    public static final String PREF_LED_CALLS = "led_calls";

    /** Sent by the notification listener when the number of active notifications changes. */
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
            Log.w(TAG, "No aw22xxx LED on this device, the service is stopping");
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
            // The service may have stopped before registering.
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

        // The effects meant for charging and SMS cannot be reached on this driver
        // (see LedController): the available ones that best convey the idea are used
        // in their place.
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
