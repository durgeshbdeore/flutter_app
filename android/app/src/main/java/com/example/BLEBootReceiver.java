package com.example.flutter_app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

public class BLEBootReceiver extends BroadcastReceiver {
  private static final String TAG = "BLEBootReceiver";

  @Override
  public void onReceive(Context context, Intent intent) {
    String action = intent.getAction();
    Log.d(TAG, "Received action: " + action);

    if (Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_REBOOT.equals(action) ||
        Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) {
      Log.d(TAG, "Starting service after boot");
      Intent serviceIntent = new Intent(context, BLEForegroundService.class);
      context.startForegroundService(serviceIntent);
    }
  }
}