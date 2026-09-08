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
 * Dà una funzione ai tasti programmabili sulla scocca e ai gesti sul sensore
 * di impronte.
 *
 * I due tasti arrivano entrambi da mtk-kpd: quello arancione come KEY_F5
 * (scancode 63) e quello sotto come KEY_CAMERA (212). Nel firmware di fabbrica
 * era il framework a intercettarli, con le impostazioni custom_key_pkg_onepress
 * e custom_key_pkg_longpress; qui si usa invece il meccanismo previsto da
 * LineageOS, che chiama questa classe per ogni tasto prima di consegnarlo
 * all'app in primo piano.
 *
 * I gesti del sensore di impronte arrivano invece da un secondo input device,
 * sf-keys, creato dal driver sunwave-fp. Verificato con getevent: il tocco
 * arriva come F10 e i due scorrimenti trasversali come DPAD_LEFT e DPAD_RIGHT
 * (il sensore risolve un asse solo; gli scorrimenti nell'altro verso vengono
 * classificati come tocco). Non sono attivi di serie: la HAL li riporta solo
 * con <navigation>true</navigation> in /vendor/etc/sw_config.xml.
 *
 * Restituire null significa "tasto consumato". Per i due tasti della scocca
 * l'azione "nessuna" lascia proseguire l'evento, che mantiene il comportamento
 * predefinito di Android. Per il sensore di impronte vale il contrario:
 * "nessuna" **consuma**, perché lasciar passare DPAD_LEFT/RIGHT farebbe
 * spostare il fuoco nelle app a ogni sfioramento del sensore, cosa che nessuno
 * si aspetta. Chi quel comportamento lo vuole sceglie l'azione "dpad".
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

        // Si agisce al rilascio, e una sola volta: i tasti tenuti premuti
        // generano ripetizioni che altrimenti farebbero lampeggiare la torcia.
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
                // Il sensore e' l'unica sorgente di questi tre su questo
                // telefono, ma una tastiera USB o Bluetooth no: senza il
                // controllo sul device, collegarne una farebbe sparire le
                // frecce direzionali.
                return "sf-keys".equals(event.getDevice() != null
                        ? event.getDevice().getName() : null);
            default:
                return false;
        }
    }

    /**
     * I gesti sul sensore, a differenza dei tasti della scocca, vanno gestiti
     * su entrambe le metà dell'evento: consumare solo il rilascio lascerebbe
     * passare la pressione, e l'app riceverebbe un DPAD spaiato.
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

        // "dpad" e' l'unica azione che lascia proseguire l'evento cosi' com'e':
        // serve a chi vuole davvero le frecce direzionali dal sensore.
        if (ACTION_DPAD.equals(action)) {
            return event;
        }

        // "indietro" si ottiene riscrivendo il keycode invece di iniettare un
        // evento nuovo: PhoneWindowManager usa l'evento che restituiamo, quindi
        // pressione e rilascio restano accoppiati e nell'ordine giusto.
        if (ACTION_BACK.equals(action)) {
            return remap(event, KeyEvent.KEYCODE_BACK);
        }

        // Le azioni restanti scattano una sola volta, al rilascio; la pressione
        // si consuma in silenzio.
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

        // Anche con "nessuna azione" l'evento si consuma: vedi il commento in
        // testa alla classe.
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
        // togglePanel() invece di expand/collapse con uno stato nostro: il
        // pannello si chiude anche con uno scorrimento sullo schermo, e un
        // booleano qui si desincronizzerebbe alla prima volta.
        statusBar.togglePanel();
    }

    private boolean launchApp(String packageName) {
        if (packageName == null) {
            return false;
        }
        final PackageManager pm = mContext.getPackageManager();
        final Intent intent = pm.getLaunchIntentForPackage(packageName);
        if (intent == null) {
            Log.w(TAG, "Nessuna activity da avviare per " + packageName);
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
            Log.e(TAG, "Torcia non disponibile", e);
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
