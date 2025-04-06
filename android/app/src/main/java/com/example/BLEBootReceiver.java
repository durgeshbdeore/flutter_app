package com.example.flutter_bluetooth;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

public class BLEBootReceiver extends BroadcastReceiver {
    private static final String TAG = "BLEBootReceiver";
    private static final String PREFS_NAME = "BLEPrefs";
    private static final String KEY_DEVICE_ADDRESS = "DEVICE_ADDRESS";

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.d(TAG, "Boot completed event received");

        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String deviceAddress = prefs.getString(KEY_DEVICE_ADDRESS, null);

        if (deviceAddress != null) {
            Log.d(TAG, "Restarting BLEForegroundService with device: " + deviceAddress);
            Intent serviceIntent = new Intent(context, BLEForegroundService.class);
            serviceIntent.putExtra("DEVICE_ADDRESS", deviceAddress);
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent);
            } else {
                context.startService(serviceIntent);
            }
        } else {
            Log.w(TAG, "No device address found. Service not restarted.");
        }
    }
}
