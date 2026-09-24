package com.dmt195.debtdestroyer.Debts;


import android.app.Activity;
import android.app.AlertDialog;
import android.app.Dialog;
import android.app.DialogFragment;
import android.content.DialogInterface;
import android.os.Bundle;
import android.view.View;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageButton;
import android.widget.TextView;
import com.dmt195.debtdestroyer.R;

/**
 * Created by new on 29/06/13.
 */
public class FragmentAddDebtDialog extends DialogFragment {

    public static final int CREDIT_CARD = 0;
    public static final int LOAN = 1;
    public static final int FAMILY_FRIENDS = 2;

    EditText debtName;
    EditText debtBalance;
    EditText aprEntry;
    EditText minPayAbs;
    EditText minPayPercent;
    CheckBox canOverPay;
    ImageButton deleteButton;
    AlertDialog dialog;

    int debtType;
    int elID;

    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        }

    public static FragmentAddDebtDialog newInstance(boolean isNew, int id, int debtType){
        FragmentAddDebtDialog fragment = new FragmentAddDebtDialog();
        Bundle args = new Bundle();
        args.putBoolean("IS_NEW", isNew);
        args.putInt("ID", id);
        args.putInt("DEBT_TYPE",debtType);
        fragment.setArguments(args);
        return fragment;
    }

    @Override
    public Dialog onCreateDialog(Bundle savedInstanceState){
        View v = getActivity().getLayoutInflater().inflate(R.layout.fragment_add_debt,null);
        DebtItem tempDebt;// = new DebtItem();
        debtName = (EditText) (v != null ? v.findViewById(R.id.et_debt_name) : null);
        debtBalance = (EditText)v.findViewById(R.id.et_balance);
        TextView aprPrompt = (TextView)v.findViewById(R.id.tv_APR);
        aprEntry = (EditText)v.findViewById(R.id.et_APR);
        TextView minPaymentPrompt = (TextView)v.findViewById(R.id.tv_min_pay);
        minPayPercent = (EditText)v.findViewById(R.id.et_min_pay_pc);
        TextView orAbsText = (TextView)v.findViewById(R.id.tv_or);
        TextView pcSymbol = (TextView)v.findViewById(R.id.tv_pc);
        canOverPay = (CheckBox)v.findViewById(R.id.cb_overpay);
        minPayAbs = (EditText)v.findViewById(R.id.et_min_pay);
        deleteButton = (ImageButton)v.findViewById(R.id.delButton);
        tempDebt = new DebtItem("",0,0,0,0,0,0,true);

        String titleText = "";
        String titlePre;
        final Boolean isNew = getArguments().getBoolean("IS_NEW");

        //Need to know some things up front
        if (isNew){
            titlePre = "New ";
            debtType = getArguments().getInt("DEBT_TYPE",0);

        } else {
            titlePre = "Edit ";
            elID = getArguments().getInt("ID",0);
            tempDebt = DebtListAdapter.debtList.get(elID);
            debtType=tempDebt.getType();
        }


        switch (debtType){
            case CREDIT_CARD:
                minPaymentPrompt.setText("Minimum Monthly Payment");
                minPayPercent.setVisibility(View.VISIBLE);
                orAbsText.setVisibility(View.VISIBLE);
                canOverPay.setVisibility(View.GONE);
                canOverPay.setChecked(true);
                titleText = titlePre + "Credit Card";
                break;
            case LOAN:
                minPaymentPrompt.setText("Regular Monthly Payment");
                minPayPercent.setText("0");
                minPayPercent.setVisibility(View.GONE);
                orAbsText.setVisibility(View.GONE);
                canOverPay.setVisibility(View.VISIBLE);
                canOverPay.setChecked(false);
                titleText = titlePre + "Loan";
                pcSymbol.setVisibility(View.GONE);
                break;
            case FAMILY_FRIENDS:
                minPaymentPrompt.setText("Agreed Monthly Payment");
                minPayPercent.setText("0");
                minPayPercent.setVisibility(View.GONE);
                orAbsText.setVisibility(View.GONE);
                canOverPay.setVisibility(View.GONE);
                canOverPay.setChecked(true);
                aprEntry.setText("0");
                aprEntry.setVisibility(View.GONE);
                aprPrompt.setVisibility(View.GONE);
                pcSymbol.setVisibility(View.GONE);
                titleText = "Friends/Family Loan";
                break;
        }

        if (isNew){
            deleteButton.setVisibility(View.GONE);

        } else {
            extractValuesIntoDialog(tempDebt);
            deleteButton.setVisibility(View.VISIBLE);
            deleteButton.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View view) {
                    ManageDebtsActivity.DebtList.removeDebtByID(elID);
                    dialog.dismiss();
                    ManageDebtsActivity.DebtList.notifyDataSetChanged();
                }
            });
        }


        TextView cur = (TextView)v.findViewById(R.id.tv_cur_symbol);
        TextView cur1 = (TextView)v.findViewById(R.id.tv_cur_symbol1);
        cur.setText(ManageDebtsActivity.currencySym);
        cur1.setText(ManageDebtsActivity.currencySym);

        dialog = new AlertDialog.Builder(getActivity())
                .setView(v)
                .setTitle(titleText)
                .setPositiveButton(android.R.string.ok, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        if (isNew){
                            /* ManageDebtsActivity.DebtList.addDebt(); */
                            addThisDebt(debtType);
                            ManageDebtsActivity.DebtList.notifyDataSetChanged();
                        } else {
                            //modify debt
                            ManageDebtsActivity.DebtList.removeDebtByID(elID);
                            addThisDebt(debtType);
                            ManageDebtsActivity.DebtList.notifyDataSetChanged();
                        }
                        dismiss();
                    }
                })
                .setNegativeButton(android.R.string.cancel, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        dismiss();
                    }
                })
                .create();

        return dialog;

    }

    /* The activity that creates an instance of this dialog fragment must
     * implement this interface in order to receive event callbacks.
     * Each method passes the DialogFragment in case the host needs to query it. */
    public interface AddDebtListener {
        public void onDialogPositiveClick(DialogFragment dialog);
        public void onDialogNegativeClick(DialogFragment dialog);
    }

    // Use this instance of the interface to deliver action events
    AddDebtListener mListener;

    // Override the Fragment.onAttach() method to instantiate the NoticeDialogListener
    @Override
    public void onAttach(Activity activity) {
        super.onAttach(activity);
        // Verify that the host activity implements the callback interface
        try {
            // Instantiate the NoticeDialogListener so we can send events to the host
            mListener = (AddDebtListener) activity;
        } catch (ClassCastException e) {
            // The activity doesn't implement the interface, throw exception
            throw new ClassCastException(activity.toString()
                    + " must implement NoticeDialogListener");
        }
    }

    private void extractValuesIntoDialog(DebtItem oldDebt) {
        debtName.setText(oldDebt.getName());
        debtBalance.setText(String.format("%.2f",oldDebt.getBalance()));
        aprEntry.setText(String.format("%.2f",oldDebt.getApr()));
        minPayAbs.setText(String.format("%.2f",oldDebt.getMinPaymentAbsolute()));
        minPayPercent.setText(String.format("%.2f", oldDebt.getMinPaymentPercent()));
        if (oldDebt.getCanOverPay()){
            canOverPay.setChecked(true);
        } else {
            canOverPay.setChecked(false);
        }

    }

    private void addThisDebt(int type) {
        DebtItem tempDebt;// = new DebtItem();
        String name = "";
        float balance = 0;
        float apr = 0;
        float payAbs = 0;
        float payPC = 0;
        boolean overPayChk;

        if(debtName.length()!=0){
            name = debtName.getText().toString();
        }
        if(debtBalance.length()!=0){
            balance = Float.parseFloat(debtBalance.getText().toString());
        }
        if(aprEntry.length()!=0){
            apr = Float.parseFloat(aprEntry.getText().toString());
        }
        if(minPayAbs.length()!=0){
            payAbs = Float.parseFloat(minPayAbs.getText().toString());
        }
        if(minPayPercent.length()!=0){
            payPC = Float.parseFloat(minPayPercent.getText().toString());
        }
        overPayChk = canOverPay.isChecked();

        tempDebt = new DebtItem(name,type,balance,apr,payAbs,payPC,balance,overPayChk);
        ManageDebtsActivity.DebtList.addDebt(tempDebt);
    }
}