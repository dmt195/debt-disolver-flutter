package com.dmt195.debtdestroyer;

import android.app.AlertDialog;
import android.app.Dialog;
import android.app.DialogFragment;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TableLayout;
import android.widget.TableRow;
import android.widget.TextView;

import com.dmt195.debtdestroyer.Debts.DebtItem;
import com.dmt195.debtdestroyer.Debts.DebtListAdapter;
import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;


/**
 * Created by new on 17/08/13.
 */
public class FragmentMinPayments extends DialogFragment {

    AlertDialog dialog;
    TableLayout table;
    TextView balance_summary;
    String confirmText = "OK";

    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
    }

    public static FragmentMinPayments newInstance(){
        FragmentMinPayments fragment = new FragmentMinPayments();
        return fragment;
    }

    @Override
    public Dialog onCreateDialog(Bundle savedInstanceState){
        View v = getActivity().getLayoutInflater().inflate(R.layout.fragment_list_min_payments,null);

        table = (TableLayout) (v != null ? v.findViewById(R.id.table_min_pay) : null);
        balance_summary = (TextView) v.findViewById(R.id.textView4);
        final int padding = 4;
        int noOfDebts = DebtListAdapter.debtList.size();
        float runningMin = 0;
        float runningInt = 0;
        for (int debtItem = 0; debtItem < noOfDebts; debtItem++){
            DebtItem tempDebt = DebtListAdapter.debtList.get(debtItem);
            TableRow row = new TableRow(v.getContext());
            TextView t = new TextView(v.getContext());
            t.setText(tempDebt.getName());
            t.setPadding(padding, padding, padding, padding);
            row.addView(t);
            TextView t1 = new TextView(v.getContext());
            float minPayAbs = tempDebt.getMinPaymentAbsolute();
            float minPayPer = tempDebt.getMinPaymentPercent()*tempDebt.getBalance()/100;
            if (minPayAbs>minPayPer){
                t1.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,minPayAbs));
                runningMin = runningMin + minPayAbs;
            } else {
                t1.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,minPayPer));
                runningMin = runningMin + minPayPer;
            }
            t1.setPadding(padding,padding,padding,padding);
            row.addView(t1);
            TextView t2 = new TextView(v.getContext());
            float interestToApply = tempDebt.getBalance()*(tempDebt.getApr() / 1200);
            t2.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,interestToApply));
            runningInt = runningInt + interestToApply;
            t2.setPadding(padding,padding,padding,padding);
            row.addView(t2);
            table.addView(row, new TableLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }

        TableRow row2 = new TableRow(v.getContext());
        TextView t3 = new TextView(v.getContext());
        t3.setText("Totals:");
        t3.setPadding(padding, padding, padding, padding);
        t3.setTypeface(null, Typeface.BOLD);
        row2.addView(t3);

        TextView t4 = new TextView(v.getContext());
        t4.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,runningMin));
        t4.setPadding(padding,padding,padding,padding);
        t4.setTypeface(null, Typeface.BOLD);
        row2.addView(t4);
        TextView t5 = new TextView(v.getContext());
        t5.setText(String.format("%s%.2f",ManageDebtsActivity.currencySym,runningInt));
        t5.setPadding(padding,padding,padding,padding);
        t5.setTypeface(null, Typeface.BOLD);
        row2.addView(t5);
        table.addView(row2, new TableLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        balance_summary.setText(String.format("%s%.2f = budget,\n%s%.2f = min. recommended.",ManageDebtsActivity.currencySym, ManageDebtsActivity.monthlyAmount, ManageDebtsActivity.currencySym, Math.max(ManageDebtsActivity.DebtList.getTotalMinPayment(),ManageDebtsActivity.DebtList.getFirstMonthPayable()+0.01)));
//        if (ManageDebtsActivity.monthlyAmount < ManageDebtsActivity.DebtList.getTotalMinPayment() * 1.1) {
//
//            confirmText = "Apply Recommended";
//        }


        if(ManageDebtsActivity.monthlyAmount>=ManageDebtsActivity.DebtList.getFirstMonthPayable()){
        dialog = new AlertDialog.Builder(getActivity())
                .setView(v).setTitle(getResources().getString(R.string.min_payments))
                .setPositiveButton(confirmText, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        dismiss();
                    }
                })
                .setNeutralButton(getResources().getString(R.string.change_budget), new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        Intent intent = new Intent(getActivity().getApplicationContext(), MyPreferenceActivity.class);
                        dismiss();
                        startActivity(intent);
                    }
                })
                .create();
        }else {
            dialog = new AlertDialog.Builder(getActivity())
                    .setView(v).setTitle(getResources().getString(R.string.budget_too_low))
                    .setNeutralButton(getResources().getString(R.string.change_budget), new DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(DialogInterface dialogInterface, int i) {
                            Intent intent = new Intent(getActivity().getApplicationContext(), MyPreferenceActivity.class);
                            dismiss();
                            startActivity(intent);
                        }
                    })
                    .create();
        }

        return dialog;


    }
}