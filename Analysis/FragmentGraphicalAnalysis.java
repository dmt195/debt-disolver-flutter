package com.dmt195.debtdestroyer.Analysis;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.support.v4.app.Fragment;
import android.util.DisplayMetrics;
import android.util.Log;
import android.util.TypedValue;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.R;
import com.dmt195.debtdestroyer.Solutions.Solution;

import org.achartengine.ChartFactory;
import org.achartengine.chart.PieChart;
import org.achartengine.chart.TimeChart;
import org.achartengine.model.CategorySeries;
import org.achartengine.model.TimeSeries;
import org.achartengine.model.XYMultipleSeriesDataset;
import org.achartengine.renderer.BasicStroke;
import org.achartengine.renderer.DefaultRenderer;
import org.achartengine.renderer.SimpleSeriesRenderer;
import org.achartengine.renderer.XYMultipleSeriesRenderer;
import org.achartengine.renderer.XYSeriesRenderer;

import java.sql.Time;
import java.util.Date;
import java.util.List;

/**
 * Created by new on 22/08/13.
 */



public class FragmentGraphicalAnalysis extends Fragment {

    Solution solution;
    LinearLayout graphView;
    LinearLayout pieView;
    LinearLayout pieViewContainer;
    private final static long DAY = 86400000;
    float txtMed;

    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
    }

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container, Bundle savedInstanceState) {
        View view = inflater.inflate(R.layout.fragment_graph_analysis, container, false);
        solution = AnalyseActivity.solList.getItem(0);
        graphView = (LinearLayout)view.findViewById(R.id.view_graph_balances);
        pieView = (LinearLayout)view.findViewById(R.id.view_graph_pie);
        pieViewContainer = (LinearLayout)view.findViewById(R.id.card_graph);
        DisplayMetrics metrics = getActivity().getResources().getDisplayMetrics();
        txtMed = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 10, metrics);

        graphView.addView(ChartFactory.getTimeChartView(getActivity(),getDebtDataset(),getDebtRenderer(),"MMM yy"));
        if(solution.getTotalInterest()>0){
            pieViewContainer.setVisibility(View.VISIBLE);
            pieView.addView(InterestPieChart());
        } else {
            pieViewContainer.setVisibility(View.GONE);
        }

        return view;

    }

    @Override
    public void onAttach(Activity activity) {
        super.onAttach(activity);

    }

    @Override
    public void onResume() {
        super.onResume();

    }



    public static FragmentGraphicalAnalysis newInstance(String message) {
        {
            FragmentGraphicalAnalysis f = new FragmentGraphicalAnalysis();
            Bundle bdl = new Bundle(1);
            bdl.putString("EXTRA_MESSAGE", message);
            f.setArguments(bdl);
            return f;
        }
    }

    private XYMultipleSeriesDataset getDebtDataset() {
        XYMultipleSeriesDataset dataset = new XYMultipleSeriesDataset();
        List<float[]> listToPlot = solution.getBalanceArrayList();
        //Add the individual graphs
        for (int j = 0; j < listToPlot.get(0).length; j++) {
            String debtName = solution.getPaymentOrder()[j];
            TimeSeries series = new TimeSeries(debtName);
            for (int i = 0; i < listToPlot.size(); i++) {
                series.add(new Date().getTime()+i*DAY*30.44, listToPlot.get(i)[j]);

            }
            dataset.addSeries(series);
        }
        //Build the totals graph
        int i=0;
        float sum;
        TimeSeries totalGraph = new TimeSeries(getString(R.string.total));
        for (float[] monthly : listToPlot) {
            // Step through the months and build the plot
            sum = 0;
            for (float aMonthly : monthly) {
                sum = sum + aMonthly;
            }
            totalGraph.add(new Date().getTime()+i*DAY*30.44,sum);
            i++;
        }
        dataset.addSeries(totalGraph);
        return dataset;
    }

    private XYMultipleSeriesRenderer getDebtRenderer() {
        BasicStroke[] strokeArray = {BasicStroke.SOLID,BasicStroke.DASHED,BasicStroke.DOTTED};
        XYMultipleSeriesRenderer renderer = new XYMultipleSeriesRenderer();
        renderer.setXTitle(getString(R.string.xaxis_title));
        renderer.setYTitle(String.format(getString(R.string.yaxis_title), ManageDebtsActivity.currencySym));
        renderer.setMarginsColor(Color.WHITE);
        renderer.setXLabelsColor(Color.DKGRAY);
        renderer.setXLabels(10);
        //renderer.setXLabelsAngle((float) 45.0);
        renderer.setGridColor(Color.DKGRAY);
        renderer.setAxesColor(Color.DKGRAY);
        renderer.setPanEnabled(false);
        for (int i=0; i<solution.getBalanceArrayList().get(0).length; i++){
            XYSeriesRenderer r = new XYSeriesRenderer();
            r.setColor(Color.DKGRAY);
//            r.setStroke(strokeArray[i%3]);
            renderer.addSeriesRenderer(r);
            //Log.d("dmt195", "rendering type " + i % 3);
        }
        XYSeriesRenderer r = new XYSeriesRenderer();
        r.setColor(Color.RED);
        r.setLineWidth((float) 2.0);

        renderer.addSeriesRenderer(r);
        renderer.setMargins(new int[] { 5, 50, 50, 0 });
        renderer.setYLabelsAlign(Paint.Align.CENTER);
        renderer.setYLabelsPadding(txtMed * (float) 0.5);
        renderer.setShowLegend(false);
        renderer.setYLabelsColor(0,Color.BLACK);
        renderer.setYLabelsAngle(270);
        renderer.setLabelsTextSize(txtMed);
        renderer.setAxisTitleTextSize(txtMed);
        renderer.setLegendTextSize(txtMed);
        renderer.setXLabelsPadding(txtMed * (float) 0.5);
	    renderer.setLabelsColor(Color.BLACK);
        //renderer.setMargins();
        return renderer;
    }

    private View InterestPieChart(){
        CategorySeries series = new CategorySeries("Capital vs Interest");
        series.add("Capital",solution.getTotalCost()-solution.getTotalInterest());
        series.add("Interest",solution.getTotalInterest());
        int[] colours = new int[] {getResources().getColor(R.color.pie_capital), getResources().getColor(R.color.pie_interest)};
        DefaultRenderer r = new DefaultRenderer();
        for (int colour : colours) {
            SimpleSeriesRenderer ssr = new SimpleSeriesRenderer();
            ssr.setColor(colour);
            ssr.setHighlighted(true);
            r.addSeriesRenderer(ssr);
        }
        r.setLabelsTextSize(txtMed*(float)1.5);
        r.setLabelsColor(Color.BLACK);
        r.setShowLegend(false);
        r.setMargins(new int[] { 0, 0, 0, 0 });
        View pieChart = ChartFactory.getPieChartView(getActivity(), series, r);
        return pieChart;
    }


}
