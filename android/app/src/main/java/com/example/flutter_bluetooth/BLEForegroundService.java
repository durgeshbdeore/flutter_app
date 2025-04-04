package com.example.flutter_bluetooth;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

public class BLEForegroundService extends Service {
    private static final String TAG = "BLEForegroundService";
    private static final String CHANNEL_ID = "BLEServiceChannel";
    private static final int RESTART_DELAY_MS = 5000;

    private BluetoothAdapter bluetoothAdapter;
    private BluetoothGatt bluetoothGatt;
    private String deviceAddress;
    private final Handler handler = new Handler();
    private PowerManager.WakeLock wakeLock;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(1, getNotification());

        // Wake Lock to prevent service from stopping
        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BLEForegroundService::WakeLock");
        wakeLock.acquire();

        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        bluetoothAdapter = bluetoothManager.getAdapter();

        registerRestartReceiver();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        deviceAddress = intent.getStringExtra("DEVICE_ADDRESS");
        if (deviceAddress != null) {
            connectToDevice(deviceAddress);
        }
        return START_STICKY; // Restart automatically if killed
    }

    private void connectToDevice(String address) {
        if (bluetoothAdapter == null || address == null) {
            Log.e(TAG, "Bluetooth adapter not initialized or invalid address.");
            stopSelf();
            return;
        }

        BluetoothDevice device = bluetoothAdapter.getRemoteDevice(address);
        if (device == null) {
            Log.e(TAG, "Device not found.");
            stopSelf();
            return;
        }

        Log.d(TAG, "Connecting to " + address);
        bluetoothGatt = device.connectGatt(this, false, gattCallback);
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                Log.d(TAG, "Connected to GATT server.");
                gatt.discoverServices();
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                Log.d(TAG, "Disconnected. Reconnecting...");
                handler.postDelayed(() -> reconnect(deviceAddress), 3000);
            }
        }
    };

    private void reconnect(String address) {
        if (bluetoothGatt != null) {
            bluetoothGatt.close();
        }
        BluetoothDevice device = bluetoothAdapter.getRemoteDevice(address);
        if (device != null) {
            Log.d(TAG, "Reconnecting to " + address);
            bluetoothGatt = device.connectGatt(this, false, gattCallback);
        }
    }

    private Notification getNotification() {
        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("BLE Service Running")
                .setContentText("Maintaining BLE connection")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .build();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_ID,
                    "BLE Service Channel",
                    NotificationManager.IMPORTANCE_LOW
            );
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(serviceChannel);
            }
        }
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        Log.d(TAG, "App removed from recent tasks. Restarting service...");
        scheduleServiceRestart();
    }

    @Override
    public void onDestroy() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
        if (bluetoothGatt != null) {
            bluetoothGatt.close();
        }
        unregisterReceiver(restartReceiver);
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void scheduleServiceRestart() {
        Intent restartServiceIntent = new Intent(getApplicationContext(), BLEForegroundService.class);
        PendingIntent restartPendingIntent = PendingIntent.getService(
                this, 1, restartServiceIntent, PendingIntent.FLAG_IMMUTABLE
        );

        AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        if (alarmManager != null) {
            long restartTime = System.currentTimeMillis() + RESTART_DELAY_MS;
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, restartTime, restartPendingIntent);
        }
    }

    private void registerRestartReceiver() {
        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_BOOT_COMPLETED);
        filter.addAction(Intent.ACTION_REBOOT);
        registerReceiver(restartReceiver, filter);
    }

    private final BroadcastReceiver restartReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            Log.d(TAG, "Device rebooted, restarting BLE service...");
            scheduleServiceRestart();
        }
    };
}
