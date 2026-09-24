package com.dmt195.debtdestroyer.Solutions;

import java.util.ArrayList;
import java.util.List;

/**
 * Created by Dave on 29/05/13.
 */
public class Solution {

    private float totalCost;
    private float totalInterest;
    public List<float[]> balanceArrayList = new ArrayList<float[]>();
    public List<float[]> paymentArrayList = new ArrayList<float[]>();
    private String[] paymentOrder;
    private int solutionType;

    public Solution(int solutionType, int timeToClear, float totalCost, float totalInterest, List<float[]> balanceArrayList, List<float[]> paymentArrayList, String[] paymentOrder) {
        this.timeToClear = timeToClear;
        this.totalCost = totalCost;
        this.totalInterest = totalInterest;
        this.balanceArrayList = balanceArrayList;
        this.solutionType = solutionType;
        this.paymentArrayList = paymentArrayList;
        this.paymentOrder = paymentOrder;
    }

    private int timeToClear;

    public float getTotalCost() {
        return totalCost;
    }

    public int getSolutionType() {
        return solutionType;
    }

    public void setTotalCost(float totalCost) {
        this.totalCost = totalCost;
    }

    public float getTotalInterest() {
        return totalInterest;
    }

    public List<float[]> getBalanceArrayList() {
        return balanceArrayList;
    }

    public List<float[]> getPaymentArrayList() {
        return paymentArrayList;
    }

    public void setPaymentArrayList(List<float[]> paymentArrayList) {
        this.paymentArrayList = paymentArrayList;
    }

    public void setTotalInterest(float totalInterest) {
        this.totalInterest = totalInterest;
    }

    public int getTimeToClear() {
        return timeToClear;
    }

    public void setTimeToClear(int timeToClear) {
        this.timeToClear = timeToClear;
    }

    public float getEquivalentInterest() {
        return totalInterest / totalCost * 100;
    }

    public String[] getPaymentOrder() {
        return paymentOrder;
    }

    public void setPaymentOrder(String[] paymentOrder) {
        this.paymentOrder = paymentOrder;
    }

}
