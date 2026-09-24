package com.dmt195.debtdestroyer.Details;

import android.app.ActionBar;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.view.ViewGroup;
import android.widget.ShareActionProvider;
import android.widget.TableLayout;
import android.widget.TableRow;
import android.widget.TextView;
import android.widget.Toast;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.R;
import com.dmt195.debtdestroyer.Solutions.ManageSolutionsActivity;
import com.dmt195.debtdestroyer.Solutions.Solution;

import org.apache.poi.hssf.usermodel.HSSFWorkbook;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.DataFormat;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.List;
import java.util.Locale;

/**
 * Activity whose sole purpose is to populate an amortisation table of the best solution.
 */
public class TableViewActivity extends Activity {

    TableLayout table;
    Solution solution = ManageSolutionsActivity.solList.getItem(0);
    static File file;
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_table);
    }

    public void onResume(){
        super.onResume();
        ActionBar ab = getActionBar();
        if (ab != null) {
            ab.setTitle(getString(R.string.table_activity_title));
            ab.setSubtitle(getString(R.string.table_activity_subtitle));
            ab.setDisplayHomeAsUpEnabled(true);
        }
        table = (TableLayout) findViewById(R.id.table_details);

        if (table!=null){
            // Use the layouts to decide whether the table is created or not. If too narrow then
            // the "rotate to see table" view will be there instead.
            createTable();
        }
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.share, menu);
//        MenuItem shareItem = menu.findItem(R.id.action_share_csv);
//        ShareActionProvider mShare = (ShareActionProvider)shareItem.getActionProvider();
        //Log.d("dmt195","In sharing case");

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
            case R.id.action_save_file:
                //TODO toast "saving file"
                String toastString = "Saving XLS file to downloads directory (" +
                        Environment.getExternalStoragePublicDirectory(
                                Environment.DIRECTORY_DOWNLOADS) +
                                        ")";
                Toast.makeText(getApplicationContext(), toastString, Toast.LENGTH_LONG).show();
                createXLSfile(solution);
                Intent sharingIntent = new Intent();
                sharingIntent.setAction(Intent.ACTION_SEND);
                sharingIntent.setType("application/vnd.ms-excel");
                sharingIntent.putExtra(Intent.EXTRA_STREAM, Uri.parse("file://" + file));
                startActivity(Intent.createChooser(sharingIntent,"These installed apps can handle the file"));
                return true;

        }
        return super.onOptionsItemSelected(item);
    }

    /*
    Creates a table into the table resource view in the activity_table layout.
    This puts balances and payments in a single cell of the table (payments in brackets).
    The first column includes the month number and the date.
    */
    private void createTable() {

        List<float[]> balances = solution.getBalanceArrayList();
        List<float[]> payments = solution.getPaymentArrayList();
        String[] paymentOrder = solution.getPaymentOrder();
        int time2clear = solution.getTimeToClear();
        int debtCount = paymentOrder.length;
        SimpleDateFormat sdf = new SimpleDateFormat("MMM y", Locale.getDefault());
        Calendar now;
        now = Calendar.getInstance();
        now.add(Calendar.MONTH,1);
        int padding = 4;
        float tempBal;

        //1st set the title row - kinda by hand
        //TODO Improve headers
        TableRow row = new TableRow(this);
        TextView t = new TextView(this);
        t.setText(getString(R.string.month));
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
        t2.setText(getString(R.string.balance_at_start));
        t2.setPadding(padding, padding, padding, padding);
        t2.setBackgroundColor(Color.WHITE);
        row.addView(t2);
        table.addView(row, new TableLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        //Next step through the rows of the payments list and add them to the table
        for (int month = 0; month < time2clear; month++){
            TableRow rows = new TableRow(this);
            rows.setPadding(padding,padding,padding,0);
            TextView t3 = new TextView(this);
            t3.setText(String.format("%d,\n%s", month, sdf.format(now.getTime())));
            t3.setPadding(padding, padding, padding, padding);
            t3.setBackgroundColor(Color.WHITE);
            rows.addView(t3);
            now.add(Calendar.MONTH,1);
            for (int debt = 0; debt < debtCount; debt++){
                TextView t4 = new TextView(this);
                tempBal = balances.get(month)[debt];
                if (tempBal!=0.0){
                    t4.setText(String.format("%s%.2f\n(%s%.2f)", ManageDebtsActivity.currencySym, balances.get(month)[debt], ManageDebtsActivity.currencySym, payments.get(month)[debt]));
                } else {
                    t4.setText("-\n-");
                }
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

    //Returns a formatted string representing the total balance in the balance array containing a number of entries
    private static String getMonthlyBalance(float[] balances, int entries) {
        float runningTotal = 0;
        for (int i=0; i < entries; i++){
            runningTotal = runningTotal + balances[i];
        }
        return String.format("%.2f",runningTotal);
    }

    //Returns a formatted string representing the total balance in the balance array containing a number of entries
    private static float getMonthlyBalanceFloat(float[] balances, int entries) {
        float runningTotal = 0;
        for (int i=0; i < entries; i++){
            runningTotal = runningTotal + balances[i];
        }
        return runningTotal;
    }

    //Returns a formatted string representing the total payments in the payments array containing a number of entries
    private static String getMonthlyPayment(float[] payments, int entries) {
        float runningTotal = 0;
        for (int i=0; i < entries; i++){
            runningTotal = runningTotal + payments[i];
        }
        return String.format("%.2f",runningTotal);
    }

    //Returns a formatted string representing the total payments in the payments array containing a number of entries
    private static float getMonthlyPaymentFloat(float[] payments, int entries) {
        float runningTotal = 0;
        for (int i=0; i < entries; i++){
            runningTotal = runningTotal + payments[i];
        }
        return runningTotal;
    }


    /*
    * A class that creates an MS Excel compatible file using the POI library.
    * It will create 2x sheets in a single workbook,
    * 1 for balances over time, and another for payments per debt over time.
    * The result in saved in external storage.
    * */
    static public void createXLSfile(Solution solution){
        Workbook workbook = new HSSFWorkbook();
        //2 sheets - 1 for balances, 1 for payments
        Sheet sheetBalances = workbook.createSheet("Balances");
        Sheet sheetPayments = workbook.createSheet("Payments");

        List<float[]> balances = solution.getBalanceArrayList();
        List<float[]> payments = solution.getPaymentArrayList();
        String[] paymentOrder = solution.getPaymentOrder();
        int time2clear = solution.getTimeToClear();
        int debtCount = paymentOrder.length;

        //1st create header of the xls file
        //1st sheet is "Month | Date | Balance (d1) | Balance (d2).. | Total Debt
        //2st sheet is "Month | Date | Payment (d1) | Payment (d2).. | Total Debt
        Row rowXLpay = sheetPayments.createRow(0);
        Cell cell = rowXLpay.createCell(0);
        cell.setCellValue("Month");
        Row rowXLbal = sheetBalances.createRow(0);
        Cell cellbal = rowXLbal.createCell(0);
        cellbal.setCellValue("Month");
        Cell cellDatePay = rowXLpay.createCell(1);
        Cell cellDateBal = rowXLbal.createCell(1);
        cellDatePay.setCellValue("Date");
        cellDateBal.setCellValue("Date");

        //Set up some styles
        DataFormat df = workbook.createDataFormat();
        CellStyle cs = workbook.createCellStyle();
        CellStyle csDate = workbook.createCellStyle();
//        cs.setDataFormat(df.getFormat("#,##0.00_);(#,##0.00")); //currency
        cs.setDataFormat(df.getFormat(String.format("%s%s", ManageDebtsActivity.currencySym, "#,##0.00_);(#,##0.00"))); //currency

        csDate.setDataFormat(df.getFormat("dd-MMM-yy"));; //date

        //sort out a date object
        Calendar now;
        now = Calendar.getInstance();
        now.add(Calendar.MONTH,1);

        for (int payment = 0; payment < debtCount; payment++) {
            // ...then come the debts in order
            Cell cell1 =rowXLpay.createCell(payment+2);
            cell1.setCellValue("Payment ("+paymentOrder[payment]+")");
            Cell cell2 = rowXLbal.createCell(payment+2);
            cell2.setCellValue("Balance ("+paymentOrder[payment]+")");
        }
        Cell cell3 = rowXLpay.createCell(debtCount+2);
        Cell cell31 = rowXLbal.createCell(debtCount+2);
        cell3.setCellValue("Total Payments");
        cell31.setCellValue("Total Balance");

        //Loop through the months - 1 per row
        for (int month = 0; month < time2clear; month++){
            //New row
            Row rowXLBal2 = sheetBalances.createRow(month+1);
            Row rowXLPay2 = sheetPayments.createRow(month+1);
            Cell cell4pay = rowXLPay2.createCell(0);
            Cell cell4bal = rowXLBal2.createCell(0);
            Cell cell4datePay = rowXLPay2.createCell(1);
            Cell cell4dateBal = rowXLBal2.createCell(1);

            //Set Month Number and date
            cell4pay.setCellValue(month);
            cell4bal.setCellValue(month);
            cell4datePay.setCellValue(now);
            cell4dateBal.setCellValue(now);
            cell4dateBal.setCellStyle(csDate);
            cell4datePay.setCellStyle(csDate);
            now.add(Calendar.MONTH, 1); //Increment the month for next time

            for (int debt = 0; debt < debtCount; debt++){
                Cell cell5 = rowXLPay2.createCell(debt+2);
                cell5.setCellStyle(cs);
                cell5.setCellValue(payments.get(month)[debt]);
                Cell cell6 = rowXLBal2.createCell(debt+2);
                cell6.setCellStyle(cs);
                cell6.setCellValue(balances.get(month)[debt]);
            }
            Cell cell7 = rowXLBal2.createCell(debtCount+2);
            cell7.setCellStyle(cs);
            cell7.setCellValue(getMonthlyBalanceFloat(balances.get(month), debtCount));
            Cell cell7pay = rowXLPay2.createCell(debtCount+2);
            cell7pay.setCellStyle(cs);
            cell7pay.setCellValue(getMonthlyPaymentFloat(payments.get(month), debtCount));
        }

        //Clean the sheets! Auto resize the columns so the users don't get too annoyed!
        for (int columnIndex = 0; columnIndex < debtCount+3; columnIndex++){
            sheetBalances.setColumnWidth(columnIndex,4000);
            sheetPayments.setColumnWidth(columnIndex,4000);
        }


        //Create the file
        try {

            File path = Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS);
            file = new File(path, "payments.xls");
            //Log.d("dmt195","Trying to write to: "+file);
            FileOutputStream fileOut = new FileOutputStream(file);
            workbook.write(fileOut);
            fileOut.close();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

}

