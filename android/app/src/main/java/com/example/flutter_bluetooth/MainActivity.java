package com.example.flutter_app;

import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
  private static final String TAG = "MainActivity";
  private static final String CHANNEL = "com.example.flutter_bluetooth/ble_service";

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    Log.d(TAG, "App started");
    // Removed startBleService() from here
  }

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
        .setMethodCallHandler(
            (call, result) -> {
              if (call.method.equals("startForegroundService")) {
                Log.d(TAG, "Starting foreground service from Dart");
                startBleService();
                result.success("Service started");
              } else {
                result.notImplemented();
              }
            });
  }

  private void startBleService() {
    Intent serviceIntent = new Intent(this, BLEForegroundService.class);
    startForegroundService(serviceIntent);
  }
}