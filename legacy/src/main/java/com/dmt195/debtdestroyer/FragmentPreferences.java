package com.dmt195.debtdestroyer;

import android.os.Bundle;
import android.preference.PreferenceFragment;

/**
 * Created by new on 09/06/13.
 */
public class FragmentPreferences extends PreferenceFragment {


    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        addPreferencesFromResource(R.xml.preferences);
    }
}