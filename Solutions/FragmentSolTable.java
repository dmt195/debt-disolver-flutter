package com.dmt195.debtdestroyer.Solutions;

import android.app.Fragment;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;

/**
 * Created by new on 01/08/13.
 */
public class FragmentSolTable extends Fragment {
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
    }



    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        return super.onCreateView(inflater, container, savedInstanceState);

    }

    public void createTable(Solution solution){
        String output;
        String row;
        List<float[]> balances = solution.getBalanceArrayList();
        List<float[]> payments = solution.getPaymentArrayList();
        String[] paymentOrder = solution.getPaymentOrder();
        int time2clear = solution.getTimeToClear();
        int debtCount = paymentOrder.length;
        SimpleDateFormat sdf = new SimpleDateFormat("MMM y", Locale.getDefault());
        Calendar now;
        now = Calendar.getInstance();

        //1st create header of the csv table
        output = "month, "; //1st col is the month
        for (String aPayment : paymentOrder) {
            output = output + aPayment + ", "; // ...then come the debts in order
        }
        output = output + "debt remaining\n"; // ...and then the total remaining for that month.
        row = "";
        //Loop through the months
        for (int month = 0; month < time2clear; month++){
            row = String.format("%s%d (%s), ", row, month, sdf.format(now.getTime()));
            now.add(Calendar.MONTH,1);
            for (int debt = 0; debt < debtCount; debt++){
                row = String.format("%s%.2f, ", row, payments.get(month)[debt]);
            }
            row = row + getMonthlyBalance(balances.get(month),debtCount);
        }
        output = output + row;
        //Log.d("dmt195",output);
//        return output;
    }


    static public String createCSVString(Solution solution){
        String output;
        String row;
        List<float[]> balances = solution.getBalanceArrayList();
        List<float[]> payments = solution.getPaymentArrayList();
        String[] paymentOrder = solution.getPaymentOrder();
        int time2clear = solution.getTimeToClear();
        int debtCount = paymentOrder.length;
        SimpleDateFormat sdf = new SimpleDateFormat("MMM y", Locale.getDefault());
        Calendar now;
        now = Calendar.getInstance();

        //1st create header of the csv table
        output = "month, "; //1st col is the month
        for (String aPayment : paymentOrder) {
            output = output + aPayment + ", "; // ...then come the debts in order
        }
        output = output + "debt remaining\n"; // ...and then the total remaining for that month.
        row = "";
        //Loop through the months
        for (int month = 0; month < time2clear; month++){
            row = String.format("%s%d (%s), ", row, month, sdf.format(now.getTime()));
            now.add(Calendar.MONTH,1);
            for (int debt = 0; debt < debtCount; debt++){
                row = String.format("%s%.2f, ", row, payments.get(month)[debt]);
            }
            row = row + getMonthlyBalance(balances.get(month),debtCount);
        }
        output = output + row;
        //Log.d("dmt195",output);
        return output;
    }

    //Returns a formatted string representing the total balance in the balance array containing a number of entries
    private static String getMonthlyBalance(float[] balances, int entries) {
        float runningTotal = 0;
        for (int i=0; i < entries; i++){
            runningTotal = runningTotal + balances[i];
        }
        return String.format("%.2f\n",runningTotal);
    }


}