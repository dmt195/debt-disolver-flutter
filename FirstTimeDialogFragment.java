package com.dmt195.debtdestroyer;

import android.app.AlertDialog;
import android.app.Dialog;
import android.app.DialogFragment;
import android.content.DialogInterface;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.webkit.WebView;
import android.widget.Button;

/**
 * Created by new on 18/11/13.
 */
public class FirstTimeDialogFragment extends DialogFragment {

    AlertDialog dialog;
    int page = 1;
    int totalPages = 3;
    String fileName;
    WebView localWebView;

    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
    }

    public static FirstTimeDialogFragment newInstance(){
        FirstTimeDialogFragment fragment = new FirstTimeDialogFragment();
        return fragment;
    }

    public Dialog onCreateDialog(Bundle savedInstanceState){
        View v = getActivity().getLayoutInflater().inflate(R.layout.first_run_dialog,null);
        localWebView = (WebView) v.findViewById(R.id.webView);
        fileName = "file:///android_res/raw/intro"+page+".html";
        localWebView.loadUrl(fileName);

        dialog = new AlertDialog.Builder(getActivity())
                .setView(v)
                .setNeutralButton(getResources().getString(R.string.next), new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {

                    }
                })
                .setNegativeButton("Skip", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        //dismiss();
                    }
                })
                .create();

        return dialog;
    }

    @Override
    public void onStart()
    {
        super.onStart();    //super.onStart() is where dialog.show() is actually called on the underlying dialog, so we have to do it after this point
        AlertDialog d = (AlertDialog)getDialog();
        if(d != null)
        {
            final Button nextButton = (Button) d.getButton(Dialog.BUTTON_NEUTRAL);
            final Button skipButton = (Button) d.getButton(Dialog.BUTTON_NEGATIVE);
            nextButton.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    page++;
                    if (page == totalPages) {
                        //Final page - remove the Next button
                        nextButton.setVisibility(View.GONE);
                        skipButton.setText("OK");

                    }
                    if (page <= totalPages) {
                        //Move on to the next page
                        fileName = "file:///android_res/raw/intro" + page + ".html";
                        localWebView.loadUrl(fileName);
                    }
                    //else dialog stays open. Make sure you have an obvious way to close the dialog especially if you set cancellable to false.
                }
            });
        }
    }


}
