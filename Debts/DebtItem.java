package com.dmt195.debtdestroyer.Debts;

import android.util.Log;

/**
 * Created by Dave on 28/05/13.
 * A Debt Item is an object for each debt type (credit card, etc)
 */

public class DebtItem {

    public String name;         // human readable name
    public float balance;      // outstanding balance on card/debt
    public float apr;          // the APR
    public float minPaymentPercent;    // the minimum payable for this debt (in percent)
    public float minPaymentAbsolute;   // the minimum payable for this item (in absolute), which ever is higher
    public float limit;        // how much balance a card may hold
    public int type;            // is the debt a credit card, a loan, etc
    public boolean canOverPay;  // only applicable to loans perhaps, can the owner pay more than the minimum amount?
    public float tempBalance;  // a running balance to use when calculating solutions
    public boolean activeInCalc;// a flag to determine whether or not to use a debt item in a calculation or not


    public DebtItem(String name, int type, float balance, float apr, float minPaymentAbsolute, float minPaymentPercent, float limit, boolean canOverPay) {
        this.name = name;
        this.apr = apr;
        this.balance = balance;
        this.minPaymentAbsolute = minPaymentAbsolute;
        this.limit = limit;
        this.type = type;
        this.canOverPay = canOverPay;
        this.tempBalance = balance;
        this.activeInCalc = true;
        this.minPaymentPercent = minPaymentPercent;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public float getBalance() {
        return balance;
    }

    public void setBalance(float balance) {
        this.balance = balance;
    }

    public float getApr() {
        return apr;
    }

    public void setApr(float apr) {
        this.apr = apr;
    }

    public float getMinPaymentAbsolute() {
        return minPaymentAbsolute;
    }

    public void setMinPaymentAbsolute(float minPayment) {
        this.minPaymentAbsolute = minPayment;
    }

    public float getMinPaymentPercent(){
        return minPaymentPercent;
    }

    public void setMinPaymentPercent(float minPayment){
        this.minPaymentPercent = minPayment;
    }

public float getMinimumPayment(){
    float tempAmount = Math.max(this.getMinPaymentAbsolute() ,(this.getMinPaymentPercent() * this.getBalance()/100));
            //Log.d("dmt195", "getMinPayment returning: " + tempAmount);
      return tempAmount;
  }

    public float getLimit() {
        return limit;
    }

    public void setLimit(float limit) {
        this.limit = limit;
    }

    public int getType() {
        return type;
    }

    public void setType(int type) {
        this.type = type;
    }

    public boolean getCanOverPay() {
        return this.canOverPay;
    }

    public void setCanOverPay(boolean canOverPay) {
        this.canOverPay = canOverPay;
    }

    public void setTempBalance(float temp){
        this.tempBalance = temp;
    }

    public boolean getActiveInCalc(){
        return activeInCalc;
    }

    public void setActiveInCalc(boolean active){
        this.activeInCalc = active;
    }



    public float getTempBalance(){
        return tempBalance;
    }


    public float payMinimum() {
        float scratch;
        if (tempBalance > 0) {
            // if a balance remains
            float minToPay;
            float minPercent = minPaymentPercent * tempBalance / 100;
            if (minPaymentAbsolute > minPercent) {
                minToPay = minPaymentAbsolute;
            } else {
                minToPay = minPercent;
            }
            if (tempBalance > minToPay) {
                // if a full min payment can be made...
                setTempBalance(tempBalance - minToPay);
                scratch = minToPay;
            } else {
                // otherwise pay only what remains...
                scratch = tempBalance;
                setTempBalance(0);
            }
        } else {
            scratch = 0;
        }
        return scratch;
    }

    public float payAsMuchAsPossible(float cashAvailable) {
        float returnSpent;
        if (tempBalance > 0){
            //a balance remains
            if (tempBalance > cashAvailable){
                // can't pay it all in one go - use all available
                setTempBalance(tempBalance-cashAvailable);
                returnSpent = cashAvailable;
            } else {
                // can pay it off (woo hoo!) so spent some cash and can pay other debts
                returnSpent = tempBalance;
				setTempBalance(0);
            }
        } else {
            // no balance remaining => spent nothing
            returnSpent = 0;
        }
        return returnSpent;
    }
}
