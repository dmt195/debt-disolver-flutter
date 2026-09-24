package com.dmt195.debtdestroyer.Solutions;

import android.app.ActionBar;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.Toast;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.MyPreferenceActivity;
import com.dmt195.debtdestroyer.R;

import java.util.Currency;
import java.util.Locale;

/**
 * Created by new on 02/06/13.
 *
 *
 */
public class ManageSolutionsActivity extends Activity {

    public static SolutionListAdapter solList = new SolutionListAdapter();
    static public final int NO_OF_SOLUTIONS = 6;


    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_solutions);
        ActionBar ab = getActionBar();
        if (ab != null) {
            ab.setTitle(getString(R.string.solutions_activity_title));
        }
        ab.setSubtitle(getString(R.string.solution_activity_sub_title));
        ab.setDisplayHomeAsUpEnabled(true);

        // Check for first run condition
        if (!ManageDebtsActivity.settings.getBoolean("solutionsHasRunBefore", false)){
            //TODO guide user to enter information...
            Toast.makeText(getApplicationContext(),
                    "This is the first time the solutions management screen has been shown. Replace toast with something useful!",
                    Toast.LENGTH_SHORT).show();
            ManageDebtsActivity.settings.edit().putBoolean("solutionsHasRunBefore",true).commit();
        }

    }

    @Override
    protected void onResume() {
        super.onResume();
        //Check from preference changes
        SharedPreferences settings  = PreferenceManager.getDefaultSharedPreferences(this);
        ManageDebtsActivity.monthlyAmount = Float.parseFloat(settings.getString("monthly", "250"));
        ManageDebtsActivity.currencySym = settings.getString("currency", Currency.getInstance(Locale.getDefault()).getSymbol());
        ManageDebtsActivity.consolidationAPR = Float.parseFloat(settings.getString("loan_apr", "4.0"));
        ManageDebtsActivity.revertAPR = Float.parseFloat((settings.getString("cc_revert_apr","15.0")));
        ManageDebtsActivity.ccTerm = Integer.parseInt((settings.getString("cc_term","15")));
        ManageDebtsActivity.ccTransferFee = Float.parseFloat((settings.getString("cc_transfer_fee","4.0")));
        ManageDebtsActivity.loanActive = settings.getBoolean("loan_active",false);
        ManageDebtsActivity.ccActive = settings.getBoolean("cc_active",false);

        //Recalculate all solutions
        redoList();
        solList.notifyDataSetChanged();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.main, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        Intent parentActivityIntent = new Intent(this, ManageDebtsActivity.class);
        Intent settingsActivity = new Intent(this, MyPreferenceActivity.class);
        switch (item.getItemId()) {
            case android.R.id.home:
                parentActivityIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                finish();
                return true;
            case R.id.action_settings:
                startActivity(settingsActivity);
                return true;
        }
        return super.onOptionsItemSelected(item);
    }

    public static void redoList() {
        solList.clear();
        for (int i=0;i< ManageSolutionsActivity.NO_OF_SOLUTIONS;i++){
            switch (i){
                case 4:
                    if (ManageDebtsActivity.loanActive){
                        solList.addSolution(ManageDebtsActivity.DebtList.solve(4, ManageDebtsActivity.monthlyAmount));
                    }
                    break;
                case 5:
                    if (ManageDebtsActivity.ccActive){
                        solList.addSolution(ManageDebtsActivity.DebtList.solve(5, ManageDebtsActivity.monthlyAmount));
                    }
                    break;
                default:
                    solList.addSolution(ManageDebtsActivity.DebtList.solve(i, ManageDebtsActivity.monthlyAmount));
                    break;
            }
        }
    }

}