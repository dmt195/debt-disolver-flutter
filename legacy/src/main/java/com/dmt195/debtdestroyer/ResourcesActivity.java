package com.dmt195.debtdestroyer;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.Menu;
import android.view.MenuItem;
import android.webkit.WebView;
import android.widget.LinearLayout;

import com.dmt195.debtdestroyer.Debts.ManageDebtsActivity;
import com.google.ads.AdRequest;
import com.google.ads.AdSize;
import com.google.ads.AdView;

/**
 * Created by new on 11/08/13.
 */
public class ResourcesActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_resources);
        // Show the Up button in the action bar.
        setupActionBar();
        WebView localWebView = (WebView) findViewById(R.id.webView1);
        localWebView.loadUrl("file:///android_res/raw/resources_main.html");

        // Create the adView
        AdView adView = new AdView(this, AdSize.BANNER, ManageDebtsActivity.AD_UNIT_ID);
        LinearLayout layout = (LinearLayout)findViewById(R.id.ad_llayout);
        layout.addView(adView);
        AdRequest r = new AdRequest();
        //r.setTesting(false);
        adView.loadAd(r);
    }

    /**
     * Set up the {@link android.app.ActionBar}.
     */
    private void setupActionBar() {

        getActionBar().setDisplayHomeAsUpEnabled(true);

    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.home_only, menu);
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

        }
        return super.onOptionsItemSelected(item);
    }
}