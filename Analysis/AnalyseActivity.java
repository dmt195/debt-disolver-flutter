package com.dmt195.debtdestroyer.Analysis;

import android.app.ActionBar;
import android.app.FragmentTransaction;
import android.support.v4.app.Fragment;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.support.v4.app.FragmentActivity;
import android.support.v4.app.FragmentManager;
import android.support.v4.app.FragmentPagerAdapter;
import android.support.v4.view.ViewPager;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.widget.LinearLayout;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.dmt195.debtdestroyer.Details.TableViewActivity;
import com.dmt195.debtdestroyer.R;
import com.dmt195.debtdestroyer.Solutions.SolutionListAdapter;
import com.google.ads.AdRequest;
import com.google.ads.AdSize;
import com.google.ads.AdView;

import java.util.ArrayList;
import java.util.Currency;
import java.util.List;
import java.util.Locale;

/**
 * Created by new on 22/08/13.
 */
public class AnalyseActivity extends FragmentActivity {

    public static SolutionListAdapter solList = new SolutionListAdapter();

    public static final int CREDIT_CARD = 0;
    public static final int LOAN = 1;
    public static final int FAMILY_FRIENDS = 2;

    public static final int HIGHEST_INT_FIRST = 0;
    public static final int LOWEST_INT_FIRST = 1;
    public static final int CONSOLIDATION_LOAN = 4;
    public static final int INT_FREE_CC = 5;
    ViewPager mViewPager;
   // TabsAdapter mTabsAdapter;
    MyPageAdapter pageAdapter;


    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_analyse);
        ActionBar ab = getActionBar();
        if (ab != null) {
            ab.setTitle("Analysis");
        }
        ab.setDisplayHomeAsUpEnabled(true);

        if(SolutionListAdapter.solutionList.get(0)==null){
            finish();
        }

        mViewPager = (ViewPager)findViewById(R.id.pager);

        if (mViewPager !=null){
            List<Fragment> fragments = getFragments();
            pageAdapter = new MyPageAdapter(getSupportFragmentManager(), fragments);
            mViewPager.setAdapter(pageAdapter);

            ab.addTab(ab.newTab().setText("Facts").setTabListener(new ActionBar.TabListener() {
                @Override
                public void onTabSelected(ActionBar.Tab tab, FragmentTransaction ft) {
                    mViewPager.setCurrentItem(0,true);

                }

                @Override
                public void onTabUnselected(ActionBar.Tab tab, FragmentTransaction ft) {

                }

                @Override
                public void onTabReselected(ActionBar.Tab tab, FragmentTransaction ft) {

                }
            }));
            ab.addTab(ab.newTab().setText("Forecast Chart").setTabListener(new ActionBar.TabListener() {

                @Override
                public void onTabSelected(ActionBar.Tab tab, FragmentTransaction ft) {
                    mViewPager.setCurrentItem(1,true);
                }

                @Override
                public void onTabUnselected(ActionBar.Tab tab, FragmentTransaction ft) {

                }

                @Override
                public void onTabReselected(ActionBar.Tab tab, FragmentTransaction ft) {

                }
            }));
            ab.addTab(ab.newTab().setText("Next Actions").setTabListener(new ActionBar.TabListener() {

                @Override
                public void onTabSelected(ActionBar.Tab tab, FragmentTransaction ft) {
                    mViewPager.setCurrentItem(2,true);
                }

                @Override
                public void onTabUnselected(ActionBar.Tab tab, FragmentTransaction ft) {

                }

                @Override
                public void onTabReselected(ActionBar.Tab tab, FragmentTransaction ft) {

                }
            }));

            mViewPager.setOnPageChangeListener(
                    new ViewPager.SimpleOnPageChangeListener() {
                        @Override
                        public void onPageSelected(int position) {
                            // When swiping between pages, select the
                            // corresponding tab.
                            getActionBar().setSelectedNavigationItem(position);
                        }
                    });


        }

        ab.setNavigationMode(ActionBar.NAVIGATION_MODE_TABS);
        ab.setDisplayShowTitleEnabled(true);



        // Check for first run condition
        if (!ManageDebtsActivity.settings.getBoolean("analysisHasRunBefore", false)){
//            Toast.makeText(getApplicationContext(),
//                    "This is the first time the analysis screen has been shown. Replace toast with something useful!",
//                    Toast.LENGTH_SHORT).show();
            ManageDebtsActivity.settings.edit().putBoolean("analysisHasRunBefore",true).commit();
        }

        // Create the adView
        AdView adView = new AdView(this, AdSize.BANNER, ManageDebtsActivity.AD_UNIT_ID);
        LinearLayout layout = (LinearLayout)findViewById(R.id.ad_layout);
        layout.addView(adView);
        AdRequest r = new AdRequest();
        //r.setTesting(false);
        adView.loadAd(r);



    }

    private List<Fragment> getFragments(){
        List<Fragment> fList = new ArrayList<Fragment>();

        fList.add(FragmentGeneralAnalysis.newInstance("Facts"));
        fList.add(FragmentGraphicalAnalysis.newInstance("Chart"));
        fList.add(FragmentNextActionsAnalysis.newInstance("Next Actions"));

        return fList;
    }


    @Override
    protected void onResume(){
        super.onResume();
        //Check from preference changes
        SharedPreferences settings  = PreferenceManager.getDefaultSharedPreferences(this);
        ManageDebtsActivity.monthlyAmount = Float.parseFloat(settings.getString("monthly", "250"));
        ManageDebtsActivity.currencySym = settings.getString("currency", Currency.getInstance(Locale.getDefault()).getSymbol());
        //Log.d("dmt195", "" + Currency.getInstance(Locale.getDefault()).getSymbol());
        ManageDebtsActivity.consolidationAPR = Float.parseFloat(settings.getString("loan_apr", "4.0"));
        ManageDebtsActivity.revertAPR = Float.parseFloat((settings.getString("cc_revert_apr","15.0")));
        ManageDebtsActivity.ccTerm = Integer.parseInt((settings.getString("cc_term","15")));
        ManageDebtsActivity.ccTransferFee = Float.parseFloat((settings.getString("cc_transfer_fee","4.0")));
        ManageDebtsActivity.loanActive = settings.getBoolean("loan_active",false);
        ManageDebtsActivity.ccActive = settings.getBoolean("cc_active",false);

        //Recalculate all solutions
        //redoList();


    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.analyse, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        Intent parentActivityIntent = new Intent(this, ManageDebtsActivity.class);
        Intent tableActivity = new Intent(this, TableViewActivity.class);
        switch (item.getItemId()) {
            case android.R.id.home:
                parentActivityIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                finish();
                return true;
            case R.id.action_see_detail_table:
                startActivity(tableActivity);
                return true;

        }
        return super.onOptionsItemSelected(item);
    }


    class MyPageAdapter extends FragmentPagerAdapter {
        private List<Fragment> fragments;

        public MyPageAdapter(FragmentManager fm, List<Fragment> fragments) {
            super(fm);
            this.fragments = fragments;
        }
        @Override
        public Fragment getItem(int position) {
            return this.fragments.get(position);
        }

        @Override
        public int getCount() {
            return this.fragments.size();
        }
    }


}