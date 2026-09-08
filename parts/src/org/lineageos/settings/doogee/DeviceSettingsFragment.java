/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.settings.doogee;

import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;

import androidx.preference.ListPreference;
import androidx.preference.Preference;
import androidx.preference.PreferenceCategory;
import androidx.preference.PreferenceFragmentCompat;
import androidx.preference.SwitchPreferenceCompat;

import org.lineageos.settings.doogee.keys.KeyHandler;
import org.lineageos.settings.doogee.led.LedService;
import org.lineageos.settings.doogee.power.ReverseChargingController;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Le impostazioni specifiche del Doogee S88 Pro: LED della scocca, tasti
 * programmabili e ricarica inversa.
 */
public class DeviceSettingsFragment extends PreferenceFragmentCompat
        implements Preference.OnPreferenceChangeListener {

    private static final String PREF_REVERSE_CHARGING = "reverse_charging";
    private static final String CATEGORY_LED = "category_led";
    private static final String CATEGORY_FINGERPRINT = "category_fingerprint";

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        setPreferencesFromResource(R.xml.device_settings, rootKey);

        final SwitchPreferenceCompat reverseCharging = findPreference(PREF_REVERSE_CHARGING);
        if (reverseCharging != null) {
            if (ReverseChargingController.isSupported()) {
                reverseCharging.setChecked(ReverseChargingController.isEnabled());
                reverseCharging.setOnPreferenceChangeListener(this);
            } else {
                reverseCharging.setVisible(false);
            }
        }

        final PreferenceCategory ledCategory = findPreference(CATEGORY_LED);
        if (ledCategory != null
                && !org.lineageos.settings.doogee.led.LedController.isSupported()) {
            ledCategory.setVisible(false);
        }

        for (String key : new String[] {
                LedService.PREF_LED_ENABLED,
                LedService.PREF_LED_CHARGING,
                LedService.PREF_LED_NOTIFICATIONS,
                LedService.PREF_LED_CALLS }) {
            final Preference pref = findPreference(key);
            if (pref != null) {
                pref.setOnPreferenceChangeListener(this);
            }
        }

        setupAppList(KeyHandler.PREF_KEY_F5_PACKAGE);
        setupAppList(KeyHandler.PREF_KEY_CAMERA_PACKAGE);

        // I gesti del sensore hanno senso solo se il lettore c'è: sulle
        // varianti senza, la categoria sparisce invece di offrire impostazioni
        // che non fanno niente.
        final PreferenceCategory fpCategory = findPreference(CATEGORY_FINGERPRINT);
        if (fpCategory != null && !requireContext().getPackageManager()
                .hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)) {
            fpCategory.setVisible(false);
        }

        setupAppList(KeyHandler.PREF_FP_TAP_PACKAGE);
        setupAppList(KeyHandler.PREF_FP_LEFT_PACKAGE);
        setupAppList(KeyHandler.PREF_FP_RIGHT_PACKAGE);
    }

    /** Riempie l'elenco delle app avviabili, per i tasti impostati su "apri un'app". */
    private void setupAppList(String key) {
        final ListPreference pref = findPreference(key);
        if (pref == null) {
            return;
        }

        final PackageManager pm = requireContext().getPackageManager();
        final Intent launcherIntent = new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER);

        final List<ApplicationInfo> apps = new ArrayList<>();
        for (android.content.pm.ResolveInfo info : pm.queryIntentActivities(launcherIntent, 0)) {
            apps.add(info.activityInfo.applicationInfo);
        }
        Collections.sort(apps, Comparator.comparing(a -> a.loadLabel(pm).toString()));

        final CharSequence[] labels = new CharSequence[apps.size()];
        final CharSequence[] values = new CharSequence[apps.size()];
        for (int i = 0; i < apps.size(); i++) {
            labels[i] = apps.get(i).loadLabel(pm);
            values[i] = apps.get(i).packageName;
        }
        pref.setEntries(labels);
        pref.setEntryValues(values);
    }

    @Override
    public boolean onPreferenceChange(Preference preference, Object newValue) {
        if (PREF_REVERSE_CHARGING.equals(preference.getKey())) {
            ReverseChargingController.setEnabled((Boolean) newValue);
            return true;
        }

        // Le preferenze del LED vengono lette dal servizio: basta svegliarlo
        // perché rivaluti che cosa mostrare.
        requireContext().startService(new Intent(requireContext(), LedService.class));
        return true;
    }
}
