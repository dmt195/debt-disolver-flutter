package com.dmt195.debtdestroyer.Details;

import android.app.ActionBar;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TableLayout;
import android.widget.TableRow;
import android.widget.TextView;
import android.widget.Toast;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.R;
import com.dmt195.debtdestroyer.Solutions.ManageSolutionsActivity;
import com.dmt195.debtdestroyer.Solutions.Solution;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;

/**
 * Created by new on 06/06/13.
 */
public class DetailsActivity extends Activity {

    View vg;
    public static int selectedSolution;
    String[] solNames;
    TextView tvBalance, tvInterest, tvPaidBy, tvEquivInterest;
    TableLayout table;
    Solution solution;
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.details_activity);
        // Get the solution passed from the solutions page
        selectedSolution = getIntent().getIntExtra("solution",0);
        solution = ManageSolutionsActivity.solList.getItem(selectedSolution);

        vg = findViewById(R.id.fragment_graph_details);
        tvBalance = (TextView)findViewById(R.id.tv_total_paid);
        tvInterest = (TextView)findViewById(R.id.tv_interest);
        tvPaidBy = (TextView)findViewById(R.id.tv_paid_by);
        tvEquivInterest = (TextView)findViewById(R.id.tv_equiv_percent);
        solNames = getResources().getStringArray(R.array.sol_types);
        table = (TableLayout) findViewById(R.id.table_details);

        // Check for first run condition
        if (!ManageDebtsActivity.settings.getBoolean("detailsHasRunBefore", false)){
            //TODO guide user to enter information...
            Toast.makeText(getApplicationContext(),
                    "Rotate the device to switch between graph and table views.",
                    Toast.LENGTH_SHORT).show();
            ManageDebtsActivity.settings.edit().putBoolean("detailsHasRunBefore",true).commit();
        }


    }

    private void setSolutionDetails() {
        SimpleDateFormat sdf = new SimpleDateFormat("MMM y", Locale.getDefault());
        Calendar now;
        int timeToClear = solution.getTimeToClear();
        now = Calendar.getInstance();
        now.add(Calendar.MONTH,timeToClear);
        float equivPercent = (solution.getTotalInterest())*100/(solution.getTotalCost());

        tvBalance.setText(String.format(getString(R.string.total_paid), ManageDebtsActivity.currencySym, solution.getTotalCost()));
        tvInterest.setText(String.format(getString(R.string.total_interest), ManageDebtsActivity.currencySym, solution.getTotalInterest()));
        tvPaidBy.setText(String.format(getString(R.string.paid_by), sdf.format(now.getTime())));
        tvEquivInterest.setText(String.format(getString(R.string.equivalent_to),equivPercent));

    }


    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.share, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        Intent parentActivityIntent = new Intent(this, ManageDebtsActivity.class);
         switch (item.getItemId()) {
            case android.R.id.home:
                parentActivityIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                finish();
                return true;

        }
        return super.onOptionsItemSelected(item);
    }

    @Override
    protected void onResume() {
        super.onResume();
        //Log.d("dmt195", "Orientation: " + getResources().getConfiguration().orientation);
        ActionBar ab = getActionBar();
        selectedSolution = getIntent().getIntExtra("solution",0);
        solution = ManageSolutionsActivity.solList.getItem(selectedSolution);

        if (ab != null) {
            ab.setTitle(getString(R.string.details_activity_title));
            ab.setSubtitle(solNames[solution.getSolutionType()]);
            ab.setDisplayHomeAsUpEnabled(true);
        }

        if (getResources().getConfiguration().orientation == 1){
            setSolutionDetails();
        } else {
            //tvTableView.setText(FragmentSolTable.createXLSfile(ManageSolutionsActivity.solList.getItem(selectedSolution)));
            createTable();
        }

    }

    private void createTable() {

        List<float[]> balances = solution.getBalanceArrayList();
        List<float[]> payments = solution.getPaymentArrayList();
        String[] paymentOrder = solution.getPaymentOrder();
        int time2clear = solution.getTimeToClear();
        int debtCount = paymentOrder.length;
        SimpleDateFormat sdf = new SimpleDateFormat("MMM y", Locale.getDefault());
        Calendar now;
        now = Calendar.getInstance();
        int padding = 4;

        //1st set the title row - kinda by hand
        TableRow row = new TableRow(this);
        TextView t = new TextView(this);
        t.setText("Month");
        row.addView(t);
        t.setPadding(padding, padding, padding, padding);
        t.setBackgroundColor(Color.WHITE);
        for (String aPayment : paymentOrder) {
            TextView t1 = new TextView(this);
            t1.setPadding(padding, padding, padding, padding);
            t1.setText(aPayment); // ...then come the debts in order
            t1.setBackgroundColor(Color.WHITE);
            row.addView(t1);
        }
        TextView t2 = new TextView(this);
        t2.setText("Balance at month start");
        t2.setPadding(padding, padding, padding, padding);
        t2.setBackgroundColor(Color.WHITE);
        row.addView(t2);
        table.addView(row, new TableLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        //Next step through the rows of the payments list and add them to the table
        for (int month = 0; month < time2clear; month++){
            TableRow rows = new TableRow(this);
            rows.setPadding(padding,padding,padding,0);
            TextView t3 = new TextView(this);
            t3.setText(String.format("%d\n(%s)", month, sdf.format(now.getTime())));
            t3.setPadding(padding, padding, padding, padding);
            t3.setBackgroundColor(Color.WHITE);
            rows.addView(t3);
            now.add(Calendar.MONTH,1);
            for (int debt = 0; debt < debtCount; debt++){
                TextView t4 = new TextView(this);
                t4.setText(String.format("%s%.2f\n(%s%.2f)", ManageDebtsActivity.currencySym, balances.get(month)[debt], ManageDebtsActivity.currencySym, payments.get(month)[debt]));
                t4.setPadding(padding, padding, padding, padding);
                t4.setBackgroundColor(Color.WHITE);
                rows.addView(t4);
            }
            TextView t4 = new TextView(this);
            t4.setText(ManageDebtsActivity.currencySym + getMonthlyBalance(balances.get(month),debtCount)+"\n-");
            t4.setPadding(padding, padding, padding, padding);
            t4.setBackgroundColor(Color.WHITE);
            rows.addView(t4);
            table.addView(rows, new TableLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        }


    }

    public String months2Time(int months){
        String returnString;
        int years;
        String pluralYears = getString(R.string.years);
        String pluralMonths = getString(R.string.months);
        if (months < 12) {
            if (months == 1) {
                pluralMonths = getString(R.string.month_singular);
            }
            returnString = String.format("%d %s", months, pluralMonths);
        } else {
            years = (int) Math.floor(months / 12);
            months = months - years * 12;
            if (years == 1) {
                pluralYears = getString(R.string.year_singular);
            }
            if (months > 0) {
                if (months == 1) {
                    pluralMonths = getString(R.string.month_singular);
                }
                returnString = String.format(getString(R.string.years_and_months), years, pluralYears, months, pluralMonths);
            } else {
                returnString = String.format("%d %s", years, pluralYears);
            }
        }
        return returnString;
    }

    //Returns a formatted string representing the total balance in the balance array containing a number of entries
    private static String getMonthlyBalance(float[] balances, int entries) {
        float runningTotal = 0;
        for (int i=0; i < entries; i++){
            runningTotal = runningTotal + balances[i];
        }
        return String.format("%.2f",runningTotal);
    }


}