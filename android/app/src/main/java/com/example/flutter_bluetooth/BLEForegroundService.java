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

    private int reconnectAttempts = 0;
    private final int MAX_RECONNECT_ATTEMPTS = 5;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
        startForeground(1, getNotification());

        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BLEForegroundService::WakeLock");
        wakeLock.acquire();

        BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
        bluetoothAdapter = bluetoothManager.getAdapter();

        registerRestartReceiver();

        // Optional: Prompt user to exclude from battery optimizations (manual interaction required)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // Uncomment to prompt user:
            /*
            Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
            */
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        deviceAddress = intent.getStringExtra("DEVICE_ADDRESS");
        if (deviceAddress != null) {
            connectToDevice(deviceAddress);
        } else {
            Log.w(TAG, "No DEVICE_ADDRESS passed to service.");
        }
        return START_STICKY;
    }

    private void connectToDevice(String address) {
        if (bluetoothAdapter == null || address == null) {
            Log.e(TAG, "Bluetooth adapter not initialized or address is null.");
            stopSelf();
            return;
        }

        if (!bluetoothAdapter.isEnabled()) {
            Log.w(TAG, "Bluetooth is OFF. Cannot connect.");
            return;
        }

        BluetoothDevice device = bluetoothAdapter.getRemoteDevice(address);
        if (device == null) {
            Log.e(TAG, "Device not found. Unable to connect.");
            stopSelf();
            return;
        }

        Log.d(TAG, "Attempting connection to device: " + address);
        bluetoothGatt = device.connectGatt(this, false, gattCallback);
    }

    private final BluetoothGattCallback gattCallback = new BluetoothGattCallback() {
        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            Log.d(TAG, "onConnectionStateChange: status=" + status + ", newState=" + newState);
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                Log.d(TAG, "Connected to GATT server. Discovering services...");
                reconnectAttempts = 0;
                gatt.discoverServices();
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                Log.d(TAG, "Disconnected from GATT server.");
                reconnectWithDelay();
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                Log.d(TAG, "Services discovered successfully.");
            } else {
                Log.w(TAG, "Service discovery failed with status: " + status);
            }
        }
    };

    private void reconnectWithDelay() {
        if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            reconnectAttempts++;
            Log.d(TAG, "Reconnection attempt " + reconnectAttempts + "/" + MAX_RECONNECT_ATTEMPTS);
            handler.postDelayed(() -> reconnect(deviceAddress), 3000);
        } else {
            Log.e(TAG, "Max reconnect attempts reached. Stopping service.");
            stopSelf();
        }
    }

    private void reconnect(String address) {
        if (bluetoothGatt != null) {
            bluetoothGatt.close();
        }
        BluetoothDevice device = bluetoothAdapter.getRemoteDevice(address);
        if (device != null) {
            Log.d(TAG, "Reconnecting to " + address);
            bluetoothGatt = device.connectGatt(this, false, gattCallback);
        } else {
            Log.e(TAG, "Reconnection failed. Device not found.");
        }
    }

    private Notification getNotification() {
        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("BLE Service Active")
                .setContentText("Maintaining Bluetooth connection in background")
                .setSmallIcon(android.R.drawable.stat_notify_sync)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_ID,
                    "BLE Background Service",
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
        Log.w(TAG, "Task removed. Scheduling restart.");
        scheduleServiceRestart();
        super.onTaskRemoved(rootIntent);
    }

    @Override
    public void onDestroy() {
        Log.w(TAG, "Service destroyed.");
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
        Intent restartIntent = new Intent(getApplicationContext(), BLEForegroundService.class);
        restartIntent.putExtra("DEVICE_ADDRESS", deviceAddress); // preserve address
        PendingIntent restartPendingIntent = PendingIntent.getService(
                this, 1, restartIntent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
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
        filter.addAction(Intent.ACTION_MY_PACKAGE_REPLACED); // App was updated
        registerReceiver(restartReceiver, filter);
    }

    private final BroadcastReceiver restartReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            Log.d(TAG, "Received restart trigger: " + intent.getAction());
            scheduleServiceRestart();
        }
    };
}
