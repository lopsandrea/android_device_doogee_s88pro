/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee.keys;

import android.app.StatusBarManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraManager;
import android.os.SystemClock;
import android.preference.PreferenceManager;
import android.util.Log;
import android.view.KeyEvent;

import com.android.internal.os.DeviceKeyHandler;

/**
 * Gives a function to the programmable keys on the case and to the gestures on
 * the fingerprint sensor.
 *
 * Both keys come from mtk-kpd: the orange one as KEY_F5 (scancode 63) and the
 * one below it as KEY_CAMERA (212). In the stock firmware the framework caught
 * them, through the custom_key_pkg_onepress and custom_key_pkg_longpress
 * settings; here we use the mechanism LineageOS provides instead, which calls
 * this class for every key before delivering it to the foreground app.
 *
 * The fingerprint sensor gestures come from a second input device, sf-keys,
 * created by the sunwave-fp driver. Verified with getevent: the tap arrives as
 * F10 and the two crosswise swipes as DPAD_LEFT and DPAD_RIGHT (the sensor
 * resolves one axis only; swipes along the other axis are classified as taps).
 * They are not on by default: the HAL reports them only with
 * <navigation>true</navigation> in /vendor/etc/sw_config.xml.
 *
 * Returning null means "key consumed". For the two case keys the "none"
 * action lets the event through, which keeps Android's default behaviour. For
 * the fingerprint sensor the opposite holds: "none" **consumes**, because
 * letting DPAD_LEFT/RIGHT through would move focus inside apps every time the
 * sensor is brushed, which nobody expects. Whoever wants that behaviour picks
 * the "dpad" action.
 */
public class KeyHandler implements DeviceKeyHandler {

    private static final String TAG = "S88ProParts";

    public static final String PREF_KEY_F5_ACTION = "key_f5_action";
    public static final String PREF_KEY_F5_PACKAGE = "key_f5_package";
    public static final String PREF_KEY_CAMERA_ACTION = "key_camera_action";
    public static final String PREF_KEY_CAMERA_PACKAGE = "key_camera_package";

    public static final String PREF_FP_TAP_ACTION = "fp_tap_action";
    public static final String PREF_FP_TAP_PACKAGE = "fp_tap_package";
    public static final String PREF_FP_LEFT_ACTION = "fp_left_action";
    public static final String PREF_FP_LEFT_PACKAGE = "fp_left_package";
    public static final String PREF_FP_RIGHT_ACTION = "fp_right_action";
    public static final String PREF_FP_RIGHT_PACKAGE = "fp_right_package";

    public static final String ACTION_NONE = "none";
    public static final String ACTION_TORCH = "torch";
    public static final String ACTION_LAUNCH_APP = "launch_app";
    public static final String ACTION_BACK = "back";
    public static final String ACTION_SHADE = "notification_shade";
    public static final String ACTION_DPAD = "dpad";

    private final Context mContext;
    private final CameraManager mCameraManager;

    private boolean mTorchEnabled;
    private String mTorchCameraId;

    public KeyHandler(Context context) {
        mContext = context;
        mCameraManager = context.getSystemService(CameraManager.class);
    }

    @Override
    public KeyEvent handleKeyEvent(KeyEvent event) {
        if (isFingerprintGesture(event)) {
            return handleFingerprintGesture(event);
        }

        // We act on release, and only once: keys held down generate repeats that would
        // otherwise make the torch flash.
        if (event.getAction() != KeyEvent.ACTION_UP || event.getRepeatCount() != 0) {
            return event;
        }

        final String actionPref;
        final String packagePref;
        switch (event.getKeyCode()) {
            case KeyEvent.KEYCODE_F5:
                actionPref = PREF_KEY_F5_ACTION;
                packagePref = PREF_KEY_F5_PACKAGE;
                break;
            case KeyEvent.KEYCODE_CAMERA:
                actionPref = PREF_KEY_CAMERA_ACTION;
                packagePref = PREF_KEY_CAMERA_PACKAGE;
                break;
            default:
                return event;
        }

        final SharedPreferences prefs =
                PreferenceManager.getDefaultSharedPreferences(mContext);
        final String action = prefs.getString(actionPref, ACTION_NONE);

        if (ACTION_NONE.equals(action)) {
            return event;
        }

        if (ACTION_TORCH.equals(action)) {
            toggleTorch();
            return null;
        }

        if (ACTION_LAUNCH_APP.equals(action)) {
            final String packageName = prefs.getString(packagePref, null);
            if (launchApp(packageName)) {
                return null;
            }
        }

        return event;
    }

    private static boolean isFingerprintGesture(KeyEvent event) {
        switch (event.getKeyCode()) {
            case KeyEvent.KEYCODE_F10:
            case KeyEvent.KEYCODE_DPAD_LEFT:
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                // The sensor is the only source of these three on this phone, but a USB or
                // Bluetooth keyboard is not: without the device check, plugging one in would
                // make the arrow keys disappear.
                return "sf-keys".equals(event.getDevice() != null
                        ? event.getDevice().getName() : null);
            default:
                return false;
        }
    }

    /**
     * Sensor gestures, unlike the case keys, have to be handled on both halves of
     * the event: consuming only the release would let the press through, and the
     * app would receive an unpaired DPAD.
     */
    private KeyEvent handleFingerprintGesture(KeyEvent event) {
        final String actionPref;
        final String packagePref;
        switch (event.getKeyCode()) {
            case KeyEvent.KEYCODE_F10:
                actionPref = PREF_FP_TAP_ACTION;
                packagePref = PREF_FP_TAP_PACKAGE;
                break;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                actionPref = PREF_FP_LEFT_ACTION;
                packagePref = PREF_FP_LEFT_PACKAGE;
                break;
            default:
                actionPref = PREF_FP_RIGHT_ACTION;
                packagePref = PREF_FP_RIGHT_PACKAGE;
                break;
        }

        final SharedPreferences prefs =
                PreferenceManager.getDefaultSharedPreferences(mContext);
        final String action = prefs.getString(actionPref, ACTION_NONE);

        // "dpad" is the only action that lets the event through as it is: it is for
        // those who genuinely want arrow keys from the sensor.
        if (ACTION_DPAD.equals(action)) {
            return event;
        }

        // "back" is obtained by rewriting the keycode rather than injecting a new
        // event: PhoneWindowManager uses the event we return, so press and release
        // stay paired and in the right order.
        if (ACTION_BACK.equals(action)) {
            return remap(event, KeyEvent.KEYCODE_BACK);
        }

        // The remaining actions fire once, on release; the press is consumed
        // silently.
        if (event.getAction() != KeyEvent.ACTION_UP || event.getRepeatCount() != 0) {
            return null;
        }

        if (ACTION_TORCH.equals(action)) {
            toggleTorch();
        } else if (ACTION_SHADE.equals(action)) {
            toggleNotificationShade();
        } else if (ACTION_LAUNCH_APP.equals(action)) {
            launchApp(prefs.getString(packagePref, null));
        }

        // Even with "no action" the event is consumed: see the comment at the top of
        // the class.
        return null;
    }

    private static KeyEvent remap(KeyEvent event, int keyCode) {
        return new KeyEvent(event.getDownTime(), event.getEventTime(),
                event.getAction(), keyCode, event.getRepeatCount(),
                event.getMetaState(), event.getDeviceId(), event.getScanCode(),
                event.getFlags(), event.getSource());
    }

    private void toggleNotificationShade() {
        final StatusBarManager statusBar =
                mContext.getSystemService(StatusBarManager.class);
        if (statusBar == null) {
            return;
        }
        // togglePanel() rather than expand/collapse with state of our own: the shade
        // also closes with a swipe on the screen, and a boolean here would fall out of
        // sync the first time.
        statusBar.togglePanel();
    }

    private boolean launchApp(String packageName) {
        if (packageName == null) {
            return false;
        }
        final PackageManager pm = mContext.getPackageManager();
        final Intent intent = pm.getLaunchIntentForPackage(packageName);
        if (intent == null) {
            Log.w(TAG, "No activity to launch for " + packageName);
            return false;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        mContext.startActivity(intent);
        return true;
    }

    private void toggleTorch() {
        if (mCameraManager == null) {
            return;
        }
        try {
            if (mTorchCameraId == null) {
                mTorchCameraId = findTorchCamera();
            }
            if (mTorchCameraId == null) {
                return;
            }
            mTorchEnabled = !mTorchEnabled;
            mCameraManager.setTorchMode(mTorchCameraId, mTorchEnabled);
        } catch (CameraAccessException | IllegalArgumentException e) {
            Log.e(TAG, "Torch unavailable", e);
            mTorchEnabled = false;
        }
    }

    private String findTorchCamera() throws CameraAccessException {
        for (String id : mCameraManager.getCameraIdList()) {
            final Boolean hasFlash = mCameraManager.getCameraCharacteristics(id)
                    .get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE);
            if (Boolean.TRUE.equals(hasFlash)) {
                return id;
            }
        }
        return null;
    }
}
