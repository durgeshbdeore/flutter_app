import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class BleController extends GetxController {
  final RxList<ScanResult> scanResults = <ScanResult>[].obs;
  final RxBool isConnected = false.obs;
  final RxBool isScanning = false.obs;
  BluetoothDevice? connectedDevice;
  Function(List<int>)? onDataReceived;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final bool debug = true;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  static const platform = MethodChannel('com.example.flutter_bluetooth/ble_service');

  @override
  void onInit() {
    super.onInit();
    initializeBluetooth();
    initNotifications();
  }

  void initializeBluetooth() {
    FlutterBluePlus.setLogLevel(debug ? LogLevel.verbose : LogLevel.none);
    FlutterBluePlus.onScanResults.listen((results) {
      scanResults.assignAll(results);
    });
  }

  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    bool allGranted = statuses[Permission.bluetoothScan]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted &&
        statuses[Permission.location]!.isGranted;

    if (!allGranted) {
      _log("Permissions denied: $statuses");
      showNotification("Please grant Bluetooth and Location permissions");
    }
    return allGranted;
  }

  Future<void> scanDevices() async {
    if (isScanning.value) {
      _log("Already scanning, skipping...");
      return;
    }

    if (!await FlutterBluePlus.isAvailable) {
      _log("Bluetooth not available");
      showNotification("Please enable Bluetooth");
      return;
    }

    if (!await requestPermissions()) {
      _log("Scanning aborted due to missing permissions");
      showNotification("Scanning requires Bluetooth and Location permissions");
      return;
    }

    scanResults.clear();
    isScanning.value = true;

    try {
      _log("Starting BLE scan...");
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      _log("Scanning started successfully");
    } catch (e) {
      _log("Scan error: $e");
      showNotification("Failed to scan: $e");
      rethrow; // Propagate to UI
    } finally {
      isScanning.value = false;
      _log("Scanning stopped");
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    _log("Connecting to ${device.id.id} (${device.name})");
    try {
      if (connectedDevice != null) {
        await connectedDevice!.disconnect();
        _connectionSubscription?.cancel();
      }

      await device.connect(timeout: const Duration(seconds: 10));
      final connectionState = await device.connectionState
          .firstWhere((state) => state != BluetoothConnectionState.connecting)
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception("Connection timed out");
      });

      if (connectionState == BluetoothConnectionState.connected) {
        _log("Connected to ${device.id.id}");
        connectedDevice = device;
        isConnected.value = true;

        // Discover services and characteristics
        var services = await device.discoverServices();
        Map<String, List<String>> serviceData = {};
        for (var service in services) {
          List<String> charUuids = service.characteristics.map((c) => c.uuid.toString()).toList();
          serviceData[service.uuid.toString()] = charUuids;
        }

        // Write connection details to log file
        await _saveConnectionDetailsToLog(device.id.id, serviceData);
        _log("Saved connection details to log file");

        await _setupNotifications(device);
        _monitorConnectionState(device);

        // Start background service after user-initiated connection
        try {
          await platform.invokeMethod('startForegroundService');
          _log("Started foreground service");
        } catch (e) {
          _log("Error starting service: $e");
        }

        showNotification('Connected to ${device.name.isNotEmpty ? device.name : device.id.id}');
      } else {
        throw Exception("Unexpected state: $connectionState");
      }
    } catch (e) {
      _log("Connection error: $e");
      isConnected.value = false;
      showNotification('Failed to connect to ${device.name.isNotEmpty ? device.name : device.id.id}');
      await device.disconnect();
      connectedDevice = null;
      rethrow;
    }
  }

  Future<void> _saveConnectionDetailsToLog(String deviceAddress, Map<String, List<String>> serviceData) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/ble_connection_log.json');
      final data = {
        'deviceAddress': deviceAddress,
        'services': serviceData,
      };
      await file.writeAsString(jsonEncode(data));
      _log("Connection log saved: ${file.path}");
    } catch (e) {
      _log("Error saving connection log: $e");
    }
  }

  void _monitorConnectionState(BluetoothDevice device) {
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      _log("Connection state: $state");
      isConnected.value = state == BluetoothConnectionState.connected;
    });
  }

  Future<void> _setupNotifications(BluetoothDevice device) async {
    try {
      var services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == "6e400001-b5a3-f393-e0a9-e50e24dcca9e") {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == "6e400003-b5a3-f393-e0a9-e50e24dcca9e" && characteristic.properties.notify) {
              await characteristic.setNotifyValue(true);
              characteristic.lastValueStream.listen((value) {
                if (onDataReceived != null) onDataReceived!(value);
                _log("Data: $value");
              });
              _log("Notifications enabled for ${characteristic.uuid}");
            }
          }
        }
      }
    } catch (e) {
      _log("Notification setup error: $e");
    }
  }

  Future<void> writeCharacteristic(String data) async {
    if (connectedDevice == null) {
      _log("No device connected to write to");
      showNotification("No device connected");
      return;
    }
    try {
      var services = await connectedDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == "6e400001-b5a3-f393-e0a9-e50e24dcca9e") {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == "6e400002-b5a3-f393-e0a9-e50e24dcca9e" && characteristic.properties.write) {
              await characteristic.write(utf8.encode(data));
              _log("Wrote data: $data to ${characteristic.uuid}");
              return;
            }
          }
          _log("No writable characteristic found in service 6e400001-b5a3-f393-e0a9-e50e24dcca9e");
        }
      }
      _log("Service 6e400001-b5a3-f393-e0a9-e50e24dcca9e not found");
    } catch (e) {
      _log("Error writing characteristic: $e");
      showNotification("Failed to send command: $e");
    }
  }

  Future<void> disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      _log("Disconnected from ${connectedDevice!.id.id}");
    }
    isConnected.value = false;
    _connectionSubscription?.cancel();
  }

  Future<void> forgetDevice() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/ble_connection_log.json');
      if (await file.exists()) {
        await file.delete();
        _log("Connection log deleted");
      }
      await disconnectDevice();
      showNotification("Device forgotten");
    } catch (e) {
      _log("Error forgetting device: $e");
      showNotification("Failed to forget device: $e");
    }
  }

  void setOnDataReceived(Function(List<int>) callback) {
    onDataReceived = callback;
  }

  Future<void> initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> showNotification(String message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'bluetooth_channel',
      'Bluetooth Status',
      channelDescription: 'BLE connection status',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(0, 'BLE Status', message, details);
    _log("Notification: $message");
  }

  void _log(String msg) {
    if (debug) log("[BleController] $msg");
  }

  @override
  void onClose() {
    _connectionSubscription?.cancel();
    super.onClose();
  }
}