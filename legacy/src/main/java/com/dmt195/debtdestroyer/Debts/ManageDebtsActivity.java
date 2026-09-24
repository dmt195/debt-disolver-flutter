package com.dmt195.debtdestroyer.Debts;

import android.app.ActionBar;
import android.app.Activity;
import android.app.Dialog;
import android.app.DialogFragment;
import android.app.FragmentManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.drawable.ColorDrawable;
import android.os.AsyncTask;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.Toast;

import com.dmt195.debtdestroyer.FirstTimeDialogFragment;
import com.dmt195.debtdestroyer.FragmentMinPayments;
import com.dmt195.debtdestroyer.Analysis.AnalyseActivity;
import com.dmt195.debtdestroyer.MyPreferenceActivity;
import com.dmt195.debtdestroyer.R;
import com.google.ads.AdRequest;
import com.google.ads.AdSize;
import com.google.ads.AdView;

import org.json.JSONException;

import java.io.BufferedInputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Currency;
import java.util.Locale;

import static com.dmt195.debtdestroyer.Analysis.AnalyseActivity.CONSOLIDATION_LOAN;
import static com.dmt195.debtdestroyer.Analysis.AnalyseActivity.HIGHEST_INT_FIRST;
import static com.dmt195.debtdestroyer.Analysis.AnalyseActivity.INT_FREE_CC;
import static com.dmt195.debtdestroyer.Analysis.AnalyseActivity.LOWEST_INT_FIRST;
import static com.dmt195.debtdestroyer.Analysis.AnalyseActivity.solList;


/**
 * Created by new on 01/06/13.
 */
public class ManageDebtsActivity extends Activity implements FragmentAddDebtDialog.AddDebtListener {

    public static DebtListAdapter DebtList = new DebtListAdapter();

    public static final int CREDIT_CARD = 0;
    public static final int LOAN = 1;
    public static final int FAMILY_FRIENDS = 2;
    private static final String DIALOG_ADD = "addGeneric";
    private static boolean clear2continue;
    public final static String AD_UNIT_ID = "ca-app-pub-3611480488934998/8084462063";
    public static float monthlyAmount;
    public static String currencySym;
    public static float consolidationAPR;
    public static float revertAPR;
    public static int ccTerm;
    public static float ccTransferFee;
    public static boolean loanActive;
    public static boolean ccActive;
    public static SharedPreferences settings;

    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        settings  = PreferenceManager.getDefaultSharedPreferences(this);
        // Check for first run condition
        if (!settings.getBoolean("debtsHasRunBefore", false)){
            FirstTimeDialogFragment firstDialog;
            firstDialog = FirstTimeDialogFragment.newInstance();
            firstDialog.show(getFragmentManager(),"FirstDialog");
            settings.edit().putString("currency",Currency.getInstance(Locale.getDefault()).getSymbol());
            settings.edit().putBoolean("debtsHasRunBefore",true).commit();
        } else {
            currencySym = settings.getString("currency", Currency.getInstance(Locale.getDefault()).getSymbol());
        }



        monthlyAmount = Float.parseFloat(settings.getString("monthly", "250"));
        consolidationAPR = Float.parseFloat(settings.getString("loan_apr", "4.0"));
        revertAPR = Float.parseFloat((settings.getString("cc_revert_apr","15.0")));
        ccTerm = Integer.parseInt((settings.getString("cc_term","15")));
        ccTransferFee = Float.parseFloat((settings.getString("cc_transfer_fee","4.0")));
        loanActive = settings.getBoolean("loan_active",false);
        ccActive = settings.getBoolean("cc_active",false);


        setContentView(R.layout.activity_manage);
        ActionBar ab = getActionBar();
        if (ab != null) {
            ab.setTitle(getString(R.string.manage_debts_activity_title));
            ab.setSubtitle(getString(R.string.manage_debts_activity_subtitle));
            ab.setDisplayHomeAsUpEnabled(false);
        }

        clear2continue = true;

        // Create the adView
        AdView adView = new AdView(this, AdSize.BANNER, AD_UNIT_ID);
        LinearLayout layout = (LinearLayout)findViewById(R.id.ad_layout);
        layout.addView(adView);
        AdRequest r = new AdRequest();
        //r.setTesting(false);
        adView.loadAd(r);

        // My code starts...







        ImageButton butAddDebtCC = (ImageButton) findViewById(R.id.but_add_cc);
        ImageButton butAddDebtLoan = (ImageButton) findViewById(R.id.but_add_loan);
        ImageButton butAddDebtFnF = (ImageButton) findViewById(R.id.but_add_fnf);

        View.OnClickListener AddDebtListener = new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                FragmentManager fm = getFragmentManager();
                FragmentAddDebtDialog dialog;
                switch (view.getId()){
                    case R.id.but_add_cc:
                        //Toast.makeText(getApplicationContext(), "Add credit card pressed", Toast.LENGTH_SHORT).show();
                        dialog = FragmentAddDebtDialog.newInstance(true,0,CREDIT_CARD);
                        dialog.show(fm,DIALOG_ADD);
                        break;
                    case R.id.but_add_loan:
                        //Toast.makeText(getApplicationContext(), "Add bank loan pressed", Toast.LENGTH_SHORT).show();
                        dialog = FragmentAddDebtDialog.newInstance(true,0,LOAN);
                        dialog.show(fm,DIALOG_ADD);
                        break;
                    case R.id.but_add_fnf:
                        //Toast.makeText(getApplicationContext(), "Add friends and family loan pressed", Toast.LENGTH_SHORT).show();
                        dialog = FragmentAddDebtDialog.newInstance(true,0,FAMILY_FRIENDS);
                        dialog.show(fm,DIALOG_ADD);
                        break;
                }
                DebtList.notifyDataSetChanged();

            }
        };


        butAddDebtCC.setOnClickListener(AddDebtListener);
        butAddDebtLoan.setOnClickListener(AddDebtListener);
        butAddDebtFnF.setOnClickListener(AddDebtListener);

        if (DebtList.getCount()<1){
            try {
                readFile("default");

                new redoListInBackground().execute();
            } catch (IOException e) {

                e.printStackTrace();
            } catch (JSONException e) {

                e.printStackTrace();
            }

        }
        DebtList.notifyDataSetChanged();
    }

    @Override
    protected void onPause() {
        //Log.d("dmt195","onPause called");
        try {
            createFile("default");
        } catch (IOException e) {
            //Log.d("dmt195","IOException");
            e.printStackTrace();
        } catch (JSONException e) {
            //Log.d("dmt195","JSONException");
            e.printStackTrace();
        }
        super.onPause();
    }

    @Override
    protected void onResume() {
        //Log.d("dmt195","onResume called");
        SharedPreferences settings  = PreferenceManager.getDefaultSharedPreferences(this);
        monthlyAmount = Float.parseFloat(settings.getString("monthly", "250"));
        currencySym = settings.getString("currency", Currency.getInstance(Locale.getDefault()).getSymbol());
        consolidationAPR = Float.parseFloat(settings.getString("loan_apr", "4.0"));
        revertAPR = Float.parseFloat((settings.getString("cc_revert_apr","15.0")));
        ccTerm = Integer.parseInt((settings.getString("cc_term","15")));
        ccTransferFee = Float.parseFloat((settings.getString("cc_transfer_fee","4.0")));
        loanActive = settings.getBoolean("loan_active",false);
        ccActive = settings.getBoolean("cc_active",false);
        clear2continue = true;

        if (DebtList.getCount()<1){
            DebtList.notifyDataSetChanged();
            try {
                readFile("default");
                //Log.d("dmt195","reading in default");
                DebtList.notifyDataSetChanged();

            } catch (IOException e) {
                e.printStackTrace();
            } catch (JSONException e) {

                e.printStackTrace();
            }

        }

        super.onResume();

    }

    public void createFile(String fName) throws IOException, JSONException {
        //Writes the element list to disk in JSON format
        String text = DebtList.getJSONArray();
        FileOutputStream fos = openFileOutput(fName, MODE_PRIVATE);
        fos.write(text.getBytes());
        fos.close();
    }

    public void readFile(String fName) throws IOException, JSONException {

        FileInputStream fis = openFileInput(fName);
        BufferedInputStream bis = new BufferedInputStream(fis);
        StringBuffer b = new StringBuffer();
        while (bis.available() != 0) {
            char c = (char) bis.read();
            b.append(c);
        }

        bis.close();
        fis.close();

        DebtList.convertJSONArrayToElements(b.toString());
    }


    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.menu_manage_debts, menu);
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
            case (R.id.action_settings):
                startActivity(settingsActivity);
                return true;
            case (R.id.action_calc_min_pay):
                if (DebtList.getCount()==0){
                    Toast.makeText(getApplicationContext(),"No debts entered! Nothing to pay!", Toast.LENGTH_LONG).show();
                } else {
                    //Toast.makeText(getApplicationContext(),"Dialog box with breakdown of min payments...", Toast.LENGTH_LONG).show();
                    FragmentManager fm = getFragmentManager();
                    FragmentMinPayments dialog = FragmentMinPayments.newInstance();
                    dialog.show(fm, DIALOG_ADD);
                }
                return true;
            case (R.id.action_see_solutions):
                double minPlusTen = DebtList.getFirstMonthPayable();
                if (DebtList.getCount()==0){
                    Toast.makeText(getApplicationContext(),
                            "No debts to solve!",
                            Toast.LENGTH_LONG).show();
                } else {
                    if (minPlusTen<=monthlyAmount){
                        while (!clear2continue){
                            try {
                                Thread.sleep(100);
                                //Log.d("dmt195","Waiting for clear2compute to be false");
                            } catch (InterruptedException e) {
                                e.printStackTrace();
                            }
                        }
                        solveAllDirect();
                        Intent solActive = new Intent(getApplicationContext(),AnalyseActivity.class);
                        startActivity(solActive);
                    } else {
                        FragmentManager fm = getFragmentManager();
                        FragmentMinPayments dialog = FragmentMinPayments.newInstance();
                        dialog.show(fm, DIALOG_ADD);
                    }
                }
                return true;
            case (R.id.show_help_overlay):
                onCoachMark();
                return true;
        }
        return super.onOptionsItemSelected(item);
    }


    public void onCoachMark(){

        final Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.getWindow().setBackgroundDrawable(new ColorDrawable(android.graphics.Color.TRANSPARENT));
        dialog.setContentView(R.layout.coach_mark_debts);
        dialog.setCanceledOnTouchOutside(true);
        //for dismissing anywhere you touch
        View masterView = dialog.findViewById(R.id.master_coach_view);
        masterView.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                dialog.dismiss();
            }
        });
        dialog.show();
    }

    @Override
    public void onDialogPositiveClick(DialogFragment dialog) {
        //new redoListInBackground().execute();
    }

    @Override
    public void onDialogNegativeClick(DialogFragment dialog) {
        //new redoListInBackground().execute();
    }

    public class redoListInBackground extends AsyncTask<Void,Void,Boolean> {

        @Override
        protected void onPreExecute(){
            clear2continue = false;
        }

        @Override
        protected void onPostExecute(Boolean ready){
            clear2continue = true;
            solList.notifyDataSetChanged();
            //Log.d("dmt195","In onPostExecute");
        }

        @Override
        protected void onProgressUpdate(Void... values){
        }

        @Override
        protected synchronized Boolean doInBackground(Void... Params){
            //Log.d("dmt195","In redoList method.");
            solveAll();
            return Boolean.TRUE;
        }

        private void solveAll(){
            solList.clear();

            //Add some loans to the list for analysis
            solList.addSolution(ManageDebtsActivity.DebtList.solve(HIGHEST_INT_FIRST, monthlyAmount));
            solList.addSolution(ManageDebtsActivity.DebtList.solve(LOWEST_INT_FIRST, monthlyAmount));

            //Add a 110% monthly payment option
            solList.addSolution(ManageDebtsActivity.DebtList.solve(HIGHEST_INT_FIRST, monthlyAmount * (float) 1.1));

            solList.addSolution(ManageDebtsActivity.DebtList.solve(CONSOLIDATION_LOAN, monthlyAmount));
            solList.addSolution(ManageDebtsActivity.DebtList.solve(INT_FREE_CC, monthlyAmount));

            solList.notifyDataSetChanged();

        }


    }

    private void solveAllDirect(){
        solList.clear();

        //Add some loans to the list for analysis
        solList.addSolution(ManageDebtsActivity.DebtList.solve(HIGHEST_INT_FIRST, monthlyAmount));
        solList.addSolution(ManageDebtsActivity.DebtList.solve(LOWEST_INT_FIRST, monthlyAmount));

        //Add a 110% monthly payment option
        solList.addSolution(ManageDebtsActivity.DebtList.solve(HIGHEST_INT_FIRST, monthlyAmount * (float) 1.1));

        solList.addSolution(ManageDebtsActivity.DebtList.solve(CONSOLIDATION_LOAN, monthlyAmount));
        solList.addSolution(ManageDebtsActivity.DebtList.solve(INT_FREE_CC, monthlyAmount));

        solList.notifyDataSetChanged();

    }
}