package com.dmt195.debtdestroyer.Solutions;

import android.app.ListFragment;
import android.content.Intent;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ListView;

import com.dmt195.debtdestroyer.Details.DetailsActivity;

public class FragmentSolList extends ListFragment {
    private static final String DIALOG_ADD = "addGeneric";

    @Override
    public View onCreateView(LayoutInflater inflater, ViewGroup container,Bundle savedInstanceState) {

        //ArrayAdapter<String> adapter = new ArrayAdapter<String>(inflater.getContext(), android.R.layout.simple_list_item_1,countries);
        setListAdapter(ManageSolutionsActivity.solList);
        return super.onCreateView(inflater, container, savedInstanceState);


    }

    @Override
    public void onListItemClick(ListView l, View v, int position, long id) {
        //super.onListItemClick(l, v, position, id);
        //Log.d("dmt195", String.format("List item number %d clicked.", position));
        Intent solActive = new Intent(l.getContext(),DetailsActivity.class);
        //solActive.putExtra("solution",ManageSolutionsActivity.solList.getItem(position).getSolutionType());
        solActive.putExtra("solution",position);
        startActivity(solActive);
    }


    public void updateView(){
        ManageSolutionsActivity.solList.notifyDataSetChanged();
        setListAdapter(ManageSolutionsActivity.solList);
    }

}