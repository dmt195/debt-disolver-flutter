package com.dmt195.debtdestroyer.Debts;

import android.app.FragmentManager;
import android.app.ListFragment;
import android.os.Bundle;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ListView;

import com.dmt195.debtdestroyer.R;

public class FragmentDebtList extends ListFragment {
    private static final String DIALOG_ADD = "addGeneric";

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container,Bundle savedInstanceState) {
         View view = inflater.inflate(R.layout.fragment_list_view, container, false);

        //ArrayAdapter<String> adapter = new ArrayAdapter<String>(inflater.getContext(), android.R.layout.simple_list_item_1,countries);
        setListAdapter(ManageDebtsActivity.DebtList);
        return view; //super.onCreateView(inflater, container, savedInstanceState);


    }

    @Override
    public void onListItemClick(ListView l, View v, int position, long id) {
        super.onListItemClick(l, v, position, id);
        //Log.d("dmt195", String.format("List item number %d clicked.", position));
        //ManageDebtsActivity.DebtList.removeDebtByID(position);
        FragmentManager fm = getFragmentManager();
        FragmentAddDebtDialog dialog;
        dialog = FragmentAddDebtDialog.newInstance(false,position,ManageDebtsActivity.DebtList.getItem(position).getType());
        dialog.show(fm != null ? fm : null,DIALOG_ADD);
        ManageDebtsActivity.DebtList.notifyDataSetChanged();
    }


    public void updateView(){
        ManageDebtsActivity.DebtList.notifyDataSetChanged();
        setListAdapter(ManageDebtsActivity.DebtList);
    }

}