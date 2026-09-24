package com.dmt195.debtdestroyer.Solutions;

import android.content.res.Resources;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.ProgressBar;
import android.widget.RelativeLayout;
import android.widget.TextView;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.R;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.Locale;

/**
 * Created by new on 24/07/13.
 */
public class SolutionListAdapter extends BaseAdapter {

    public static ArrayList<Solution> solutionList = new ArrayList<Solution>();

    public void addSolution(Solution sol){
        solutionList.add(sol);
    }


    @Override
    public int getCount() {
        return solutionList.size();
    }

    @Override
    public Solution getItem(int i) {
        return solutionList.get(i);
    }

    @Override
    public long getItemId(int i) {
        return 0;
    }

    public void delete(int i){
        solutionList.remove(i);
    }

    @Override
    public View getView(int i, View view, ViewGroup parent) {
        if (view==null){
            LayoutInflater inflater = LayoutInflater.from(parent.getContext());
            view = inflater.inflate(R.layout.solution_list_item,parent,false);
        }
        Calendar now= Calendar.getInstance();
        Collections.sort(solutionList, new SolutionInterestCompareLowest());
        Resources res = view.getContext().getResources();
        String[] solTypeArray = res.getStringArray(R.array.sol_types);
        Solution solTemp = solutionList.get(i);
        int solType = solTemp.getSolutionType();
        TextView solName = (TextView)view.findViewById(R.id.sol_name);
        ProgressBar slider = (ProgressBar)view.findViewById(R.id.progressBar);
        TextView capital = (TextView)view.findViewById(R.id.tv_capital);
        TextView interest = (TextView)view.findViewById(R.id.tv_interest);
        TextView paidBy = (TextView)view.findViewById(R.id.tv_paid_by);
        TextView intEquiv = (TextView)view.findViewById(R.id.tv_equiv);
        solName.setText(solTypeArray[solType]);
        slider.setMax(1000);
        slider.setProgress((int) (1000-solTemp.getEquivalentInterest()*10));
        interest.setText(String.format("Cost: %s%.2f", ManageDebtsActivity.currencySym,solTemp.getTotalInterest()));
        capital.setText(String.format("Capital: %s%.2f", ManageDebtsActivity.currencySym,solTemp.getTotalCost()-solTemp.getTotalInterest()));
        intEquiv.setText(String.format("Equiv to: %.1f%%",solTemp.getEquivalentInterest()));

        SimpleDateFormat sdf = new SimpleDateFormat("MMM y", Locale.getDefault());
        int timeToClear = solTemp.getTimeToClear();
        now.add(Calendar.MONTH,timeToClear);
        //Log.d("dmt195",String.format("Paid by %s",sdf.format(now.getTime())));
        paidBy.setText(String.format("Paid by %s", sdf.format(now.getTime())));

        return view;
    }

    public void clear() {
        solutionList.clear();
    }

    class SolutionInterestCompareLowest implements Comparator<Solution> {
        public int compare(Solution s1, Solution s2) {
            return (int) (s1.getTotalInterest() - s2.getTotalInterest());
        }
    }

}