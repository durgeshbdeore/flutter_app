package com.example.flutter_app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothManager;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

import org.json.JSONObject;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.UUID;

public class BLEForegroundService extends Service {
  private static final String TAG = "BLEForegroundService";
  private static final String CHANNEL_ID = "BLEServiceChannel";
  private static final int NOTIFICATION_ID = 1;

  private BluetoothAdapter bluetoothAdapter;
  private BluetoothGatt bluetoothGatt;
  private String deviceAddress;
  private String notifyServiceUuid;
  private String notifyCharUuid;
  private NotificationManager notificationManager;
  private final Handler handler = new Handler(Looper.getMainLooper());

  @Override
  public void onCreate() {
    super.onCreate();
    Log.d(TAG, "Service created");

    notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
    createNotificationChannel();
    startForeground(NOTIFICATION_ID, getNotification("Service started"));

    BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
    bluetoothAdapter = bluetoothManager.getAdapter();
    if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
      Log.e(TAG, "Bluetooth unavailable");
      updateNotification("Bluetooth unavailable");
      stopSelf();
    }
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    Log.d(TAG, "onStartCommand");
    loadConnectionDetailsFromLog();
    if (deviceAddress != null) {
      connectToDevice();
    } else {
      Log.w(TAG, "No device address in log file");
      updateNotification("No device to connect");
    }
    return START_STICKY;
  }

  private void loadConnectionDetailsFromLog() {
    try {
      File dir = getApplicationContext().getFilesDir().getParentFile();
      File logFile = new File(dir, "app_flutter/ble_connection_log.json");
      if (logFile.exists()) {
        String jsonString = new String(java.nio.file.Files.readAllBytes(logFile.toPath()), StandardCharsets.UTF_8);
        JSONObject json = new JSONObject(jsonString);
        deviceAddress = json.getString("deviceAddress");

        JSONObject services = json.getJSONObject("services");
        Iterator<String> keys = services.keys();
        while (keys.hasNext()) {
          String serviceUuid = keys.next();
          if (serviceUuid.equals("6e400001-b5a3-f393-e0a9-e50e24dcca9e")) {
            notifyServiceUuid = serviceUuid;
            org.json.JSONArray chars = services.getJSONArray(serviceUuid);
            for (int i = 0; i < chars.length(); i++) {
              String charUuid = chars.getString(i);
              if (charUuid.equals("6e400003-b5a3-f393-e0a9-e50e24dcca9e")) {
                notifyCharUuid = charUuid;
                break;
              }
            }
          }
        }
        Log.d(TAG, "Loaded from log: deviceAddress=$deviceAddress, notifyServiceUuid=$notifyServiceUuid, notifyCharUuid=$notifyCharUuid");
      } else {
        Log.w(TAG, "Log file not found: " + logFile.getPath());
      }
    } catch (Exception e) {
      Log.e(TAG, "Error reading log file: " + e.getMessage());
    }
  }

  private void connectToDevice() {
    if (bluetoothAdapter == null || deviceAddress == null) {
      Log.e(TAG, "Cannot connect: Bluetooth or address missing");
      updateNotification("Connection failed: No Bluetooth");
      return;
    }

    BluetoothDevice device = bluetoothAdapter.getRemoteDevice(deviceAddress);
    if (device == null) {
      Log.e(TAG, "Device not found: " + deviceAddress);
      updateNotification("Device not found");
      return;
    }

    Log.d(TAG, "Connecting to " + deviceAddress);
    updateNotification("Connecting to " + deviceAddress);
    if (bluetoothGatt != null) {
      bluetoothGatt.disconnect();
      bluetoothGatt.close();
    }
    bluetoothGatt = device.connectGatt(this, false, gattCallback);
  }

  private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
    @Override
    public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
      if (status == BluetoothGatt.GATT_SUCCESS) {
        if (newState == BluetoothGatt.STATE_CONNECTED) {
          Log.d(TAG, "Connected to " + deviceAddress);
          updateNotification("Connected to " + deviceAddress);
          gatt.discoverServices();
        } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
          Log.w(TAG, "Disconnected from " + deviceAddress);
          updateNotification("Disconnected from " + deviceAddress);
          if (bluetoothGatt != null) {
            bluetoothGatt.close();
            bluetoothGatt = null;
          }
          handler.postDelayed(() -> connectToDevice(), 5000); // Retry every 5s
        }
      } else {
        Log.e(TAG, "Connection error: " + status);
        updateNotification("Connection error: " + status);
        handler.postDelayed(() -> connectToDevice(), 5000);
      }
    }

    @Override
    public void onServicesDiscovered(BluetoothGatt gatt, int status) {
      if (status == BluetoothGatt.GATT_SUCCESS) {
        Log.d(TAG, "Services discovered");
        updateNotification("Receiving data from " + deviceAddress);
        setupNotifications(gatt);
      } else {
        Log.w(TAG, "Service discovery failed: " + status);
      }
    }

    @Override
    public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
      byte[] value = characteristic.getValue();
      Log.d(TAG, "Data: " + bytesToHex(value));
      updateNotification("Data from " + deviceAddress + ": " + bytesToHex(value));
    }
  };

  private void setupNotifications(BluetoothGatt gatt) {
    if (notifyServiceUuid == null || notifyCharUuid == null) {
      Log.w(TAG, "Notification UUIDs not loaded from log");
      return;
    }
    BluetoothGattCharacteristic characteristic = gatt.getService(UUID.fromString(notifyServiceUuid))
        .getCharacteristic(UUID.fromString(notifyCharUuid));
    if (characteristic != null) {
      gatt.setCharacteristicNotification(characteristic, true);
      BluetoothGattDescriptor descriptor = characteristic.getDescriptor(
          UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"));
      if (descriptor != null) {
        descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
        gatt.writeDescriptor(descriptor);
        Log.d(TAG, "Notifications enabled");
      }
    }
  }

  private String bytesToHex(byte[] bytes) {
    StringBuilder sb = new StringBuilder();
    for (byte b : bytes) {
      sb.append(String.format("%02x", b));
    }
    return sb.toString();
  }

  private Notification getNotification(String state) {
    Intent intent = new Intent(this, MainActivity.class);
    PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE);

    return new NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("BLE Service")
        .setContentText(state)
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentIntent(pendingIntent)
        .setOngoing(true)
        .build();
  }

  private void updateNotification(String state) {
    if (notificationManager != null) {
      Notification notification = getNotification(state);
      notificationManager.notify(NOTIFICATION_ID, notification);
      Log.d(TAG, "Notification: " + state);
    } else {
      Log.e(TAG, "NotificationManager is null, cannot update notification");
    }
  }

  private void createNotificationChannel() {
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
      NotificationChannel channel = new NotificationChannel(
          CHANNEL_ID, "BLE Service", NotificationManager.IMPORTANCE_DEFAULT);
      if (notificationManager != null) {
        notificationManager.createNotificationChannel(channel);
      } else {
        Log.e(TAG, "NotificationManager is null in createNotificationChannel");
      }
    }
  }

  @Override
  public void onDestroy() {
    super.onDestroy();
    Log.d(TAG, "Service destroyed");
    if (bluetoothGatt != null) {
      bluetoothGatt.close();
      bluetoothGatt = null;
    }
    handler.removeCallbacksAndMessages(null);
  }

  @Nullable
  @Override
  public IBinder onBind(Intent intent) {
    return null;
  }
}