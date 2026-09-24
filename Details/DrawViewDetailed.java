package com.dmt195.debtdestroyer.Details;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.View;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.R;
import com.dmt195.debtdestroyer.Solutions.ManageSolutionsActivity;
import com.dmt195.debtdestroyer.Solutions.Solution;

import java.util.List;


/**
 * Created by new on 03/06/13.
 * Draws the individual debts and the total remaining as a function of time from a given solution object
 * 
 */
public class DrawViewDetailed extends View {


    private Paint annoPaint = new Paint();
    private Paint totalPaint = new Paint();
    private Paint debtLine = new Paint();
    private Solution m;

    public DrawViewDetailed(Context context,Solution m) {
        super(context);
        this.m=m;
    }

    @Override
    public void onDraw(Canvas canvas) {

        int w = getWidth(), h = getHeight();
        final int margin = h/30;
        final int graphZeroX = margin * 4;
        final int graphZeroY = h - margin * 4;
        final int graphFullX = w - margin;
        final int graphFullY = 0;

        final float pxPerMonth = (graphFullX - graphZeroX) / m.getTimeToClear();
        final float pxPerPound = (float) ((graphZeroY - graphFullY) / (ManageDebtsActivity.DebtList.getTotalDebt() * 1.05));

        //TODO: draw the graph here
        annoPaint.setColor(Color.GRAY);
        annoPaint.setStyle(Paint.Style.STROKE);
        //annoPaint.setStrokeWidth(h/400);

        totalPaint.setColor(Color.RED);
        totalPaint.setStyle(Paint.Style.STROKE);
        totalPaint.setStrokeWidth(h/200);
        totalPaint.setAntiAlias(true);


        debtLine.setColor(Color.DKGRAY);
        debtLine.setStyle(Paint.Style.STROKE);
        debtLine.setStrokeWidth(h/400);
        debtLine.setAntiAlias(true);

        List<float[]> listToPlot = m.getBalanceArrayList();
        int noOfDataSets = listToPlot.get(0).length;


        // Draw individual entries
        for (int j = 0; j < noOfDataSets; j++) {
            int i = 0;
            Path debtPath = new Path();
            for (float[] monthly : listToPlot) {
                if (i == 0) {
                    debtPath.moveTo(graphZeroX, graphZeroY - monthly[j] * pxPerPound);
                } else {
                    debtPath.lineTo(graphZeroX + i * pxPerMonth, graphZeroY - monthly[j] * pxPerPound);
                }
                i++;
            }

            canvas.drawPath(debtPath, debtLine);
        }

        // Draw sum terms (total balance)
        int i = 0;
        float sum;
        Path totalGraph = new Path();
        for (float[] monthly : listToPlot) {
            // Step through the months and build the plot
            sum = 0;
            for (float aMonthly : monthly) {
                sum = sum + aMonthly;
            }
            if (i == 0) {
                totalGraph.moveTo(graphZeroX, graphZeroY - sum * pxPerPound);
            } else {
                totalGraph.lineTo(graphZeroX + i * pxPerMonth, graphZeroY - sum * pxPerPound);
            }
            i++;
            canvas.drawPath(totalGraph, totalPaint);
        }
        totalGraph.close();

        // Draw axes last so as on top
        canvas.drawLine(graphZeroX, graphFullY, graphZeroX, graphZeroY + margin, debtLine);
        canvas.drawLine(graphZeroX - margin, graphZeroY, graphFullX, graphZeroY, debtLine);

        // Plot tick marks every 6 months
        for (int l = 0; l < m.getTimeToClear() + 6; l = l + 6) {
            canvas.drawLine(graphZeroX + l * pxPerMonth, graphZeroY, graphZeroX + l * pxPerMonth, graphZeroY + margin, debtLine);
        }

        // Plot tick mark for every 1000 pounds
        for (int l = 0; l < ManageDebtsActivity.DebtList.getTotalDebt() / 1000; l++) {
            canvas.drawLine(graphZeroX - margin, graphZeroY - l * pxPerPound * 1000, graphZeroX, graphZeroY - l * pxPerPound * 1000, debtLine);
        }

        // Draw legend to graph
        canvas.drawLine((float) (graphFullX * 0.5), graphFullY + margin, (float) (graphFullX * 0.5 + margin * 3), graphFullY + margin, totalPaint);
        annoPaint.setTextSize(h/20);
        annoPaint.setTextAlign(Paint.Align.LEFT);
        canvas.drawText(getContext().getString(R.string.legend_total_debt), (float) (graphFullX * 0.5 + margin * 4), (float) (graphFullY + margin * 1.5), annoPaint);
        canvas.drawLine((float) (graphFullX * 0.5), graphFullY + margin * 4, (float) (graphFullX * 0.5 + margin * 3), graphFullY + margin * 4, debtLine);
        canvas.drawText(getContext().getString(R.string.legend_individual_debts), (float) (graphFullX * 0.5 + margin * 4), (float) (graphFullY + margin * 4.5), annoPaint);

        // Draw axis titles
        annoPaint.setTextAlign(Paint.Align.CENTER);
        annoPaint.setTextSize((float) (h/20));
        canvas.drawText(getContext().getString(R.string.axis_title_time), (float) (graphZeroX + graphFullX) / 2, graphZeroY + margin * 3, annoPaint);
        Path vertAxisPath = new Path();
        vertAxisPath.moveTo(graphZeroX, graphZeroY);
        vertAxisPath.lineTo(graphZeroX, graphFullY);
        canvas.drawTextOnPath(getContext().getString(R.string.axis_total_balance), vertAxisPath, 0, (float) (-margin * 2), annoPaint);


    }


}
