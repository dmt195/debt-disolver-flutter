package com.dmt195.debtdestroyer.Debts;

import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.ImageView;
import android.widget.TextView;

import com.dmt195.debtdestroyer.R;
import com.dmt195.debtdestroyer.Solutions.Solution;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Created by Dave on 28/05/13.
 * <p/>
 * A place to store and interact with the list of debt items, particularly as part of a listview.
 * Also produces the solutions to debts
 */
public class DebtListAdapter extends BaseAdapter {
    public static final int CREDIT_CARD = 0;
    public static final int LOAN = 1;
    public static final int FAMILY_FRIENDS = 2;
    //private SharedPreferences settings = getPreferences(getBaseContext().MODE_PRIVATE);

    public static ArrayList<DebtItem> debtList = new ArrayList<DebtItem>();

    public void addDebt(DebtItem newDebt) {
        debtList.add(newDebt);
    }

    public void removeDebtByID(int i){
        debtList.remove(i);
    }

    @Override
    public int getCount() {
        return debtList.size();
    }

    private int getCountActive() {
        // returns the number of loan active in the calculation
        int i = debtList.size();
        //Log.d("dmt195", "count= " + i);
        int runningTotal = 0;
        if (i > 0) {
            for (DebtItem aDebtList : debtList) {
                //Log.d("dmt195", ", j = "+j);
                if (aDebtList.activeInCalc) {
                    runningTotal = runningTotal + 1;
                }
            }
        }
        return runningTotal;
    }

    @Override
    public DebtItem getItem(int i) {
        return debtList.get(i);
    }

    @Override
    public long getItemId(int i) {
        return 0;
    }

    @Override
    public View getView(int i, View view, ViewGroup parent) {
        if (view==null){
            LayoutInflater inflater = LayoutInflater.from(parent.getContext());
            view = inflater.inflate(R.layout.pretty_debt_list_item,parent,false);
        }
        DebtItem debt = debtList.get(i);
        TextView tvName = (TextView) (view != null ? view.findViewById(R.id.tv_debt_name) : null);
        TextView tvBalance = (TextView)view.findViewById(R.id.tv_debt_balance);
        //TextView tvLimit = (TextView)view.findViewById(R.id.tv_limit);
        TextView tvAPR = (TextView)view.findViewById(R.id.tv_APR);
        ImageView lvBG = (ImageView)view.findViewById(R.id.iv_listview_bg);
        TextView debtTV = (TextView)view.findViewById(R.id.tv_debt_type);

        tvName.setText(debt.getName());
        tvAPR.setText(String.format("%.1f \u0025%",debt.getApr()));
        String minPayExpression = "Min payment";
        switch(debt.getType()){
            //Set the background image depending on debt type
            case CREDIT_CARD:
                lvBG.setImageResource(R.drawable.cc_bg);
                debtTV.setText("[Credit Card]");
                break;
            case LOAN:
                lvBG.setImageResource(R.drawable.bank_bg);
                minPayExpression = "Regular payment";
                debtTV.setText("[Bank Loan]");
                break;
            case FAMILY_FRIENDS:
                lvBG.setImageResource(R.drawable.fnf_bg);
                minPayExpression = "Agreed payment";
                debtTV.setText("[Friends/Family Loan]");
                break;
        }
        if (debt.getMinPaymentPercent()==0.0){
            tvBalance.setText(String.format("Balance: %s%.2f\n%s: %s%.0f", ManageDebtsActivity.currencySym,debt.getBalance(),minPayExpression,ManageDebtsActivity.currencySym,debt.getMinPaymentAbsolute()));
        }else {
            tvBalance.setText(String.format("Balance: %s%.2f\n%s: %s%.0f (or %.1f \u0025%)", ManageDebtsActivity.currencySym,debt.getBalance(),minPayExpression,ManageDebtsActivity.currencySym,debt.getMinPaymentAbsolute(),debt.getMinPaymentPercent()));
        }

        return view;
    }

    public float getTotalDebt() {
        int i = debtList.size();
        //Log.d("dmt195", "count= " + i);
        float runningTotal = 0;
        if (i > 0) {
            for (DebtItem aDebtList : debtList) {
                //Log.d("dmt195", ", j = "+j);
                if (aDebtList.activeInCalc) {
                    runningTotal = runningTotal + aDebtList.balance;
                }
            }
        }
        //Log.d("dmt195","TotalDebt = "+runningTotal);
        return runningTotal;

    }

    public float getTotalTempDebt() {
        int i = debtList.size();
        float runningTotal = 0;
        if (i > 0) {
            for (DebtItem aDebtList : debtList) {
                if (aDebtList.activeInCalc) {
                    runningTotal = runningTotal + aDebtList.getTempBalance();
                }
            }
        }
        //Log.d("dmt195","TotalTempDebt = "+runningTotal);
        return runningTotal;
    }

    public float getTotalMinPayment() {
        int i = debtList.size();
        resetTempBalances();
        float runningTotal = 0;
        float minToPay;
        float minPercent;
        if (i > 0) {
            for (DebtItem aDebtList : debtList) {
                if (aDebtList.activeInCalc) {
                    minPercent = aDebtList.minPaymentPercent * aDebtList.tempBalance / 100;
                    if (aDebtList.minPaymentAbsolute > minPercent) {
                        minToPay = aDebtList.minPaymentAbsolute;
                    } else {
                        minToPay = minPercent;
                    }
                    runningTotal = runningTotal + minToPay;
                }
            }
        }
        return runningTotal;
    }


    public float getFirstMonthPayable(){
        int i = debtList.size();
        resetTempBalances();
        float runningTotal = 0;
        if (i > 0) {
            for (DebtItem debt : debtList) {
                if (debt.activeInCalc) {
                    runningTotal = runningTotal + Math.max(debt.getMinimumPayment(), debt.getBalance() * debt.getApr() / 1200);
                    //Log.d("dmt195","getFirstMonthPayable running total: "+runningTotal);
                }
            }
        }


        return runningTotal;
    }

    public void resetTempBalances() {
        int i = debtList.size();
        if (i > 0) {
            for (DebtItem aDebtList : debtList) {
                aDebtList.setTempBalance(aDebtList.getBalance());
            }
        }
    }

    private void simulateMonthlyInterest() {
        int i = debtList.size();
        float interestMult;
        if (i > 0) {
            for (DebtItem debtItem : debtList) {
                interestMult = (debtItem.getApr() / 1200) + 1;
                debtItem.setTempBalance(debtItem.getTempBalance() * interestMult);
            }
        }
    }

    public void setDebtsActivity(boolean active) {
        int i = debtList.size();
        if (i > 0) {
            for (DebtItem aDebtList : debtList) {
                aDebtList.setActiveInCalc(active);
            }
        }
    }

    class DebtInterestCompareLowest implements Comparator<DebtItem> {
        public int compare(DebtItem d1, DebtItem d2) {
            return (int) (d1.getApr() - d2.getApr()) * 100;
        }
    }

    class DebtInterestCompareHighest implements Comparator<DebtItem> {
        public int compare(DebtItem d1, DebtItem d2) {
            return (int) (d2.getApr() - d1.getApr()) * 100;
        }
    }

    class DebtBalanceCompareLowest implements Comparator<DebtItem> {
        public int compare(DebtItem d1, DebtItem d2) {
            return (int) (d1.getBalance() - d2.getBalance());
        }
    }

    class DebtBalanceCompareHighest implements Comparator<DebtItem> {
        public int compare(DebtItem d1, DebtItem d2) {
            return (int) (d2.getBalance() - d1.getBalance());
        }
    }

    public Solution solve(int solutionType, float monthly) {
        // Solve the debt list using the solutionType qualifier
        // Use the solutionAmortisation list to list the monthly balances and payments
        // solutionType = 0 for highest interest first
        // solutionType = 1 for lowest interest first
        // solutionType = 2 for lowest balance first
        // solutionType = 3 for highest balance first
        // solutionType = 4 for consolidation loan
        // solutionType = 5 for low interest rate transfer

        //float monthly = ManageDebtsActivity.monthlyAmount;
        resetTempBalances();
        float monthlyToSpend;
        int month = 0;
        float tempTotal = getTotalTempDebt();
        float totalSpent = 0;
        float interestPaid;
        int activeI;
        List<float[]> balanceArrayList = new ArrayList<float[]>();
        List<float[]> paymentArrayList = new ArrayList<float[]>();
        Solution sol2Return;



        switch (solutionType) {
            case 0:
                Collections.sort(debtList, new DebtInterestCompareHighest());
                break;
            case 1:
                Collections.sort(debtList, new DebtInterestCompareLowest());
                break;
            case 2:
                Collections.sort(debtList, new DebtBalanceCompareLowest());
                break;
            case 3:
                Collections.sort(debtList, new DebtBalanceCompareHighest());
                break;
            case 4:
                setDebtsActivity(false);
                addDebt(new DebtItem("Consolidation Loan",LOAN,tempTotal,ManageDebtsActivity.consolidationAPR,monthly,0,tempTotal,false));
                break;
            case 5:
                setDebtsActivity(false);
                float transferMultiplier = ManageDebtsActivity.ccTransferFee/100+1;
                addDebt(new DebtItem("Interest Free CC",CREDIT_CARD,tempTotal*transferMultiplier,0,monthly,0,tempTotal*transferMultiplier,false));
                break;
        }
        int debtCount = getCount();

        // Check that sum of min balances can be met by the monthly sum
        if (monthly >= getTotalMinPayment()) {
            //Log.d("dmt195", "Can pay monthlies");
            // while array - while totalTempBalance !=0
            int debtCountActive = getCountActive();
            float[] paymentPlanArray = new float[debtCountActive];
            float[] minMonthSpread = new float[debtCountActive];
            float scratch;

            // Build payment order array
            String[] paymentOrder = new String[debtCountActive];
            activeI = 0;
            for (int i = 0; i < debtCount; i++) {
                if (debtList.get(i).activeInCalc){
                    paymentOrder[activeI] = debtList.get(i).getName();
                    activeI++;
                }
            }
            float[] balanceArray = new float[debtCountActive];
            //Log.d("dmt195", strArray2Str(paymentOrder));

            while (tempTotal > 0) {
                //Log.d("dmt195","Month = "+month);
                monthlyToSpend = monthly;
                simulateMonthlyInterest();

                // Distribute minimum payments
                // ---------------------------------------------------
                activeI = 0;
                for (int i = 0; i < debtCount; i++) {

                    if (debtList.get(i).activeInCalc) {
                        balanceArray[activeI] = debtList.get(i).getTempBalance();
                        //Log.d("dmt195", "Balance for " + i + " = " + debtList.get(i).getTempBalance());
                        scratch = debtList.get(i).payMinimum();
                        minMonthSpread[activeI]=scratch;
                        monthlyToSpend = monthlyToSpend - scratch;
                        activeI++;
                    }
                }
                // Spend the rest in the top priority debts
                // ----------------------------------------------------
                activeI = 0;
                for (int i = 0; i < debtCount; i++) {
                    if (debtList.get(i).activeInCalc) {
                        if (debtList.get(i).canOverPay) {
                            scratch = debtList.get(i).payAsMuchAsPossible(monthlyToSpend);
                            monthlyToSpend = monthlyToSpend - scratch;
                            //Log.d("dmt195",activeI+", "+monthlySpread[activeI]);
                        } else {
                            scratch = 0;
                        }
                        paymentPlanArray[activeI] = minMonthSpread[activeI] + scratch;
                        activeI++;
                    }
                }
                // Payment cycle complete, append arrays and calculate interest
                // ----------------------------------------------------
                // Check if interest free period has expired for transfer card
                if (month == ManageDebtsActivity.ccTerm && solutionType == 5){
                    debtList.get(debtCount-1).setApr(ManageDebtsActivity.revertAPR);
                    //Log.d("dmt195","ccTerm = "+ ManageDebtsActivity.ccTerm + ", revertAPR = "+ ManageDebtsActivity.revertAPR);
                }

                tempTotal = getTotalTempDebt();

                // Create balance and payment arrayList entries
                balanceArrayList.add(balanceArray.clone());
                paymentArrayList.add(paymentPlanArray.clone());
                month++;
                totalSpent = totalSpent + monthly - monthlyToSpend;
            }

            // Calculations complete
            // final iteration so that there's a 0,0,0 entry at the end
            for (int i = 0; i < debtCountActive; i++) {
                    balanceArray[i] = 0;
            }
            balanceArrayList.add(balanceArray.clone()); // Blank array for final balance
            paymentArrayList.add(paymentPlanArray.clone()); // Blank array for final payments (should be zeros - test!)


            // Clean up - kill the consolidation loan from the list if that is the solution type
            if (solutionType >= 4) {
                setDebtsActivity(true);
                //Log.d("dmt195","deleting loan: "+debtList.get(debtCount-1).getName());
                removeDebtByID(debtCount-1);
            }
            interestPaid = totalSpent - getTotalDebt();
            sol2Return = new Solution(solutionType, month, totalSpent, interestPaid, balanceArrayList, paymentArrayList, paymentOrder);
            return sol2Return;
        } else {
            // Not enough cash to meet minimum payments
            //Log.d("dmt195", "Can't pay monthlies");
            String[] fakeOrder = {"","",""};
            sol2Return = new Solution(solutionType, 0, 0, 0,balanceArrayList,paymentArrayList, fakeOrder);
        }
        return sol2Return;

    }

    String array2Str(float[] arrayIn) {
        String outString = "";
        for (int i = 0; i != arrayIn.length; i++) {
            if (i == 0) {
                outString = String.format("%.2f", arrayIn[0]);
            } else {
                outString = String.format("%s, %.2f",outString,arrayIn[i]);
            }
        }
        outString = "[" + outString + "]";
        return outString;
    }

    String strArray2Str(String[] arrayIn){
        String outString = "";
        for (int i = 0; i != arrayIn.length; i++) {
            if (i == 0) {
                outString = arrayIn[0];
            } else {
                outString = String.format("%s, %s",outString,arrayIn[i]);
            }
        }
        outString = "[" + outString + "]";
        return outString;
    }

    public static String getJSONArray() throws JSONException {

        JSONArray jsa = new JSONArray();

        for (DebtItem aDebtList : debtList) {
            JSONObject jso = new JSONObject();
            jso.put("name", aDebtList.name);
            jso.put("balance", aDebtList.balance);
            jso.put("type", aDebtList.type);
            jso.put("apr", aDebtList.apr);
            jso.put("canOverPay", aDebtList.canOverPay);
            jso.put("limit", aDebtList.limit);
            jso.put("minPayAbsolute", aDebtList.minPaymentAbsolute);
            jso.put("minPayPercent", aDebtList.minPaymentPercent);
            jsa.put(jso);
        }
        return jsa.toString();
    }

    public static void convertJSONArrayToElements(String b) throws JSONException {
        // Recall the data from the default file
        JSONArray data = new JSONArray(b);
        for (int i = 0; i < data.length(); i++) {
            String name = data.getJSONObject(i).getString("name");
            int type = data.getJSONObject(i).getInt("type");
            float balance = (float) data.getJSONObject(i).getDouble("balance");
            float limit = (float) data.getJSONObject(i).getDouble("limit");
            float apr = (float) data.getJSONObject(i).getDouble("apr");
            float minPayAbs = (float) data.getJSONObject(i).getDouble("minPayAbsolute");
            float minPayPer = (float) data.getJSONObject(i).getDouble("minPayPercent");
            boolean canOverPay = data.getJSONObject(i).getBoolean("canOverPay");
            debtList.add(new DebtItem(name, type, balance,apr,minPayAbs,minPayPer,limit,canOverPay));
        }
    }



}

