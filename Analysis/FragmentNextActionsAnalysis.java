package com.dmt195.debtdestroyer.Analysis;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.res.Resources;
import android.os.Bundle;
import android.support.v4.app.Fragment;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.Toast;

import com.dmt195.debtdestroyer.R;
import com.google.ads.r;

/**
 * Created by new on 22/08/13.
 */



public class FragmentNextActionsAnalysis extends Fragment {

    LinearLayout card_stop_spending;
    LinearLayout card_set_a_budget;
    LinearLayout card_consolidate;
    LinearLayout card_track;
    Resources r;
   // View.OnClickListener moreInfo;
    //LinearLayout card5;

    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        r = getResources();



    }

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        View view = inflater.inflate(R.layout.fragment_next_actions_analysis, container, false);


        card_stop_spending = (LinearLayout)view.findViewById(R.id.na_card_stop_spending);
        card_set_a_budget = (LinearLayout)view.findViewById(R.id.na_card_make_budget);
        card_consolidate = (LinearLayout)view.findViewById(R.id.na_card_consolidate);
        card_track = (LinearLayout)view.findViewById(R.id.na_card_track);

        View.OnClickListener moreInfo = new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                String message = "";
                //Log.d("dmt195","OnClick registered");
                switch (v.getId()){
                    case R.id.na_card_stop_spending :
                        //TODO
                        message= r.getString(R.string.stop_spending_details);
                        //Log.d("dmt195", "Click detected");
                        break;
                    case R.id.na_card_make_budget :
                        message= r.getString(R.string.make_a_budget_details);
                        //TODO
                        break;
                    case R.id.na_card_consolidate :
                        message = r.getString(R.string.consolidate_details);
                        //TODO
                        break;
                    case R.id.na_card_track :
                        //TODO
                        message = r.getString(R.string.time_to_track_details);
                        break;
                }
                AlertDialog.Builder builder = new AlertDialog.Builder(getActivity());//Build dialog box and show it
                builder.setMessage(message)
                .setNeutralButton("OK",new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {

                    }
                });
                builder.create().show();
            }
        };

        card_stop_spending.setOnClickListener(moreInfo);
        card_set_a_budget.setOnClickListener(moreInfo);
        card_consolidate.setOnClickListener(moreInfo);
        card_track.setOnClickListener(moreInfo);

        return view;

    }

    @Override
    public void onAttach(Activity activity) {
        super.onAttach(activity);
    }

    @Override
    public void onResume() {
        super.onResume();
    }


    public static FragmentNextActionsAnalysis newInstance(String message) {
        {
            FragmentNextActionsAnalysis f = new FragmentNextActionsAnalysis();
            Bundle bdl = new Bundle(1);
            bdl.putString("EXTRA_MESSAGE", message);
            f.setArguments(bdl);
            return f;
        }
    }
}

