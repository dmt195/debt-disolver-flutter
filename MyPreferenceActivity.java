package com.dmt195.debtdestroyer;

import android.os.Bundle;
import android.preference.PreferenceActivity;

/**
 * Created by new on 09/06/13.
 */
public class MyPreferenceActivity extends PreferenceActivity {

    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
//        addPreferencesFromResource(R.xml.preferences);
        getFragmentManager().beginTransaction().replace(android.R.id.content,
                new FragmentPreferences()).commit();
    }
}