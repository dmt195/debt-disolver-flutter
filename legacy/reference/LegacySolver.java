// Standalone port of the legacy DebtListAdapter.solve() algorithm (Debts/DebtListAdapter.java),
// with Android dependencies removed. Logic, float arithmetic and comparator bugs are kept verbatim
// so its output can be used as a reference for the Flutter payoff_engine tests.
// Run: java LegacySolver.java
import java.util.*;

public class LegacySolver {
    static final int CREDIT_CARD = 0, LOAN = 1;
    static float consolidationAPR = 4.0f, revertAPR = 15.0f, ccTransferFee = 4.0f;
    static int ccTerm = 15;

    static class DebtItem {
        String name; float balance, apr, minPaymentPercent, minPaymentAbsolute, limit; int type;
        boolean canOverPay, activeInCalc = true; float tempBalance;
        DebtItem(String name, int type, float balance, float apr, float minAbs, float minPct, float limit, boolean canOverPay) {
            this.name = name; this.type = type; this.balance = balance; this.apr = apr; this.minPaymentAbsolute = minAbs;
            this.minPaymentPercent = minPct; this.limit = limit; this.canOverPay = canOverPay; this.tempBalance = balance;
        }
        float payMinimum() {
            if (tempBalance <= 0) return 0;
            float minPercent = minPaymentPercent * tempBalance / 100;
            float minToPay = minPaymentAbsolute > minPercent ? minPaymentAbsolute : minPercent;
            if (tempBalance > minToPay) { tempBalance -= minToPay; return minToPay; }
            float s = tempBalance; tempBalance = 0; return s;
        }
        float payAsMuchAsPossible(float cash) {
            if (tempBalance <= 0) return 0;
            if (tempBalance > cash) { tempBalance -= cash; return cash; }
            float s = tempBalance; tempBalance = 0; return s;
        }
    }

    final List<DebtItem> debtList = new ArrayList<>();

    float total(boolean temp) { float t = 0; for (DebtItem d : debtList) if (d.activeInCalc) t += temp ? d.tempBalance : d.balance; return t; }
    float totalMin() {
        float t = 0;
        for (DebtItem d : debtList) { d.tempBalance = d.balance; }
        for (DebtItem d : debtList) if (d.activeInCalc) { float p = d.minPaymentPercent * d.tempBalance / 100; t += Math.max(d.minPaymentAbsolute, p); }
        return t;
    }

    String solve(int type, float monthly) {
        for (DebtItem d : debtList) d.tempBalance = d.balance;
        int month = 0; float tempTotal = total(true), totalSpent = 0;
        switch (type) {
            case 0: debtList.sort((a, b) -> (int) (b.apr - a.apr) * 100); break;   // legacy bug kept
            case 1: debtList.sort((a, b) -> (int) (a.apr - b.apr) * 100); break;   // legacy bug kept
            case 4: for (DebtItem d : debtList) d.activeInCalc = false;
                    debtList.add(new DebtItem("Consolidation Loan", LOAN, tempTotal, consolidationAPR, monthly, 0, tempTotal, false)); break;
            case 5: for (DebtItem d : debtList) d.activeInCalc = false;
                    float m = ccTransferFee / 100 + 1;
                    debtList.add(new DebtItem("Interest Free CC", CREDIT_CARD, tempTotal * m, 0, monthly, 0, tempTotal * m, false)); break;
        }
        int n = debtList.size();
        if (monthly < totalMin()) return "infeasible";
        StringBuilder order = new StringBuilder();
        for (DebtItem d : debtList) if (d.activeInCalc) order.append(d.name).append(';');
        while (tempTotal > 0 && month < 1200) {
            float toSpend = monthly;
            for (DebtItem d : debtList) d.tempBalance *= d.apr / 1200 + 1;
            for (DebtItem d : debtList) if (d.activeInCalc) toSpend -= d.payMinimum();
            for (DebtItem d : debtList) if (d.activeInCalc && d.canOverPay) toSpend -= d.payAsMuchAsPossible(toSpend);
            if (month == ccTerm && type == 5) debtList.get(n - 1).apr = revertAPR;
            tempTotal = total(true);
            month++;
            totalSpent += monthly - toSpend;
        }
        if (type >= 4) { for (DebtItem d : debtList) d.activeInCalc = true; debtList.remove(n - 1); }
        float interest = totalSpent - total(false);
        return String.format("months=%d paid=%.2f interest=%.2f order=%s", month, totalSpent, interest, order);
    }

    static void run(String label, float monthly, DebtItem... debts) {
        String[] names = {"avalanche", "lowest", "boosted", "consolidation", "transfer"};
        int[] types = {0, 1, 0, 4, 5};
        for (int i = 0; i < 5; i++) {
            LegacySolver s = new LegacySolver();
            for (DebtItem d : debts) s.debtList.add(new DebtItem(d.name, d.type, d.balance, d.apr, d.minPaymentAbsolute, d.minPaymentPercent, d.limit, d.canOverPay));
            System.out.println(label + " " + names[i] + ": " + s.solve(types[i], i == 2 ? monthly * 1.1f : monthly));
        }
    }

    public static void main(String[] args) {
        run("S1", 250, new DebtItem("Card", CREDIT_CARD, 1000, 0, 0, 0, 0, true));
        run("S2", 100, new DebtItem("Card", CREDIT_CARD, 1200, 12, 25, 2, 0, true));
        run("S3", 450,
            new DebtItem("Card A", CREDIT_CARD, 2000, 19.9f, 25, 3, 0, true),
            new DebtItem("Card B", CREDIT_CARD, 1500, 9.9f, 25, 2, 0, true),
            new DebtItem("Car loan", LOAN, 3000, 6.5f, 150, 0, 0, false));
        run("S4", 300,
            new DebtItem("Alpha", CREDIT_CARD, 1000, 18.0f, 25, 0, 0, true),
            new DebtItem("Beta", CREDIT_CARD, 1000, 18.5f, 25, 0, 0, true));
    }
}
