package com.dmt195.debtdestroyer.Analysis;

import android.app.Activity;
import android.support.v4.app.Fragment;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.R;
import com.dmt195.debtdestroyer.Solutions.SolutionListAdapter;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Locale;

/**
 * Created by new on 22/08/13.
 */



public class FragmentGeneralAnalysis extends Fragment {

    TextView tv_cost_high;
    TextView tv_cost_info;
    TextView tv_clear_date_high;
    TextView tv_clear_date_info;
    TextView tv_difference_high;
    TextView tv_difference_info;
    TextView tv_extra_high;
    TextView tv_extra_info;
    TextView tv_consolidation_high;
    TextView tv_consolidation_info;
    TextView tv_ifcc_high;
    TextView tv_ifcc_info;

    LinearLayout ll_interest_free;
    LinearLayout ll_consolidation;
    LinearLayout ll_difference;

    SolutionListAdapter solutionList;

    Float totalCost;
    Float totalCostInInt;
    int totalTime;
    Float interestSaved;
    int timeSaved;
    Float extraPerMonthPayed;
    Float savedThroughExtra;
    Float savedThroughConsol;
    int timeSavedThroughConsol;
    int timeSavedThroughIFCC;
    Float savedThroughIFCC;


    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
    }

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        View view = inflater.inflate(R.layout.fragment_general_analysis, container, false);

        tv_cost_high =          (TextView)view.findViewById(R.id.tv_cost_highlight);
        tv_cost_info =          (TextView)view.findViewById(R.id.tv_cost_info);
        tv_clear_date_high =    (TextView)view.findViewById(R.id.tv_clear_date_highlight);
        tv_clear_date_info =    (TextView)view.findViewById(R.id.tv_clear_date_info);
        tv_difference_high =    (TextView)view.findViewById(R.id.tv_difference_highlight);
        tv_difference_info =    (TextView)view.findViewById(R.id.tv_difference_info);
        tv_extra_high =         (TextView)view.findViewById(R.id.tv_extra_highlight);
        tv_extra_info =         (TextView)view.findViewById(R.id.tv_extra_info);
        tv_consolidation_high = (TextView)view.findViewById(R.id.tv_consolidation_highlight);
        tv_consolidation_info = (TextView)view.findViewById(R.id.tv_consolidation_info);
        tv_ifcc_high =          (TextView)view.findViewById(R.id.tv_ifcc_highlight);
        tv_ifcc_info =          (TextView)view.findViewById(R.id.tv_ifcc_info);
        ll_consolidation =      (LinearLayout)view.findViewById(R.id.card_consolidate);
        ll_interest_free =      (LinearLayout)view.findViewById(R.id.card_interest_free);
        ll_difference =         (LinearLayout)view.findViewById(R.id.card_difference);


        return view;

    }

    @Override
    public void onAttach(Activity activity) {
        super.onAttach(activity);
    }

    @Override
    public void onResume() {
        super.onResume();
        populateStrings();
    }

    private void populateStrings(){
        solutionList = AnalyseActivity.solList;
        totalCost = solutionList.getItem(0).getTotalCost();
        totalCostInInt = solutionList.getItem(0).getTotalInterest();
        totalTime = solutionList.getItem(0).getTimeToClear();
        interestSaved = solutionList.getItem(1).getTotalCost()-totalCost;
        timeSaved = solutionList.getItem(1).getTimeToClear()-totalTime;
        extraPerMonthPayed = ManageDebtsActivity.monthlyAmount * 0.1f;
        savedThroughExtra = totalCost - solutionList.getItem(2).getTotalCost();
        savedThroughConsol = totalCost - solutionList.getItem(3).getTotalCost();
        timeSavedThroughConsol = totalTime - solutionList.getItem(3).getTimeToClear();
        timeSavedThroughIFCC = totalTime - solutionList.getItem(4).getTimeToClear();
        savedThroughIFCC = totalCost - solutionList.getItem(4).getTotalCost();

        //Populate highlight texts
        tv_cost_high.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,totalCostInInt));
        if (interestSaved > 0.01){
            ll_difference.setVisibility(View.VISIBLE);
            tv_difference_high.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,interestSaved));
        } else {
            ll_difference.setVisibility(View.GONE);
        }
        tv_extra_high.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,savedThroughExtra));


        Calendar now= Calendar.getInstance();
        SimpleDateFormat sdf = new SimpleDateFormat("MMM y", Locale.getDefault());
        now.add(Calendar.MONTH,totalTime);
        tv_clear_date_high.setText(sdf.format(now.getTime()));
        tv_consolidation_high.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,savedThroughConsol));
        tv_ifcc_high.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,savedThroughIFCC));

        // Check that the two consolidation methods actually save money, otherwise don't show them
        if (savedThroughConsol>0.01){
            ll_consolidation.setVisibility(View.VISIBLE);
        } else {
           ll_consolidation.setVisibility(View.GONE);
        }
        if (savedThroughIFCC>0.01){
            ll_interest_free.setVisibility(View.VISIBLE);
        } else {
           ll_interest_free.setVisibility(View.GONE);
        }


        //Populate info texts
        tv_cost_info.setText(getString(R.string.costs_detail_in_card));
        tv_clear_date_info.setText(String.format(getString(R.string.clear_by_details_in_card),totalTime));
        tv_difference_info.setText(String.format(getString(R.string.difference_detail_in_card),timeSaved));
        tv_extra_info.setText(String.format(getString(R.string.extra_detail_in_card),ManageDebtsActivity.currencySym,extraPerMonthPayed));
        tv_consolidation_info.setText(String.format(getString(R.string.consolidation_detail_in_card),ManageDebtsActivity.consolidationAPR,timeSavedThroughConsol));
        tv_ifcc_info.setText(String.format(getString(R.string.ifcc_detail_in_card),ManageDebtsActivity.ccTerm,ManageDebtsActivity.revertAPR,ManageDebtsActivity.ccTransferFee));

    }

    public static FragmentGeneralAnalysis newInstance(String message) {
        {
            FragmentGeneralAnalysis f = new FragmentGeneralAnalysis();
            Bundle bdl = new Bundle(1);
            bdl.putString("EXTRA_MESSAGE", message);
            f.setArguments(bdl);
            return f;
        }
    }
}