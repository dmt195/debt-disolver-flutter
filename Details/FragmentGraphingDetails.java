package com.dmt195.debtdestroyer.Details;

import android.app.Activity;
import android.support.v4.app.Fragment;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import com.dmt195.debtdestroyer.Analysis.AnalyseActivity;

/**
 * Created by new on 03/06/13.
 *
 * Somewhere to invent the graphing of solutions
 *
 */

public class FragmentGraphingDetails extends Fragment {
    Activity thisActivity;


    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
    }

    @Override
    public void onAttach(Activity activity) {
        super.onAttach(activity);
        thisActivity = activity;
    }

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        return new DrawViewDetailed(thisActivity.getApplicationContext(), AnalyseActivity.solList.getItem(0));
    }


    public static FragmentGraphingDetails newInstance(String message) {
        FragmentGraphingDetails f = new FragmentGraphingDetails();
        Bundle bdl = new Bundle(1);
        bdl.putString("EXTRA_MESSAGE", message);
        f.setArguments(bdl);
        return f;
    }
}