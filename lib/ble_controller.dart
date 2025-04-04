import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BleController extends GetxController {
  final RxList<ScanResult> scanResults = <ScanResult>[].obs;
  final RxBool isConnected = false.obs;
  final RxBool isScanning = false.obs;
  BluetoothDevice? connectedDevice;
  Function(List<int>)? onDataReceived;
  String? lastConnectedDeviceId;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _scanTimer;

  // For Notifications
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void onInit() {
    super.onInit();
    initializeBluetooth();
    _loadLastConnectedDevice();
    initNotifications();  // Initialize notifications

    // ✅ Ensure scan results update correctly
    FlutterBluePlus.onScanResults.listen((results) {
      scanResults.assignAll(results);
    });
  }

  /// Initialize Bluetooth and auto-connect if needed
  void initializeBluetooth() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose);

  FlutterBluePlus.state.listen((state) {
    if (state == BluetoothState.on) {
      print("✅ Bluetooth is ON");
      startAutoReconnect();
    } else {
      print("❌ Bluetooth is OFF");
    }
  });
}


  /// Load last connected device from storage and attempt reconnection
  Future<void> _loadLastConnectedDevice() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    lastConnectedDeviceId = prefs.getString('lastConnectedDeviceId');
    if (lastConnectedDeviceId != null) {
      startAutoReconnect(); // ✅ Start auto-reconnect when app starts
    }
  }

  /// Initialize local notifications for connection status
  Future<void> initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon');
    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  /// Show notification
  Future<void> showNotification(String message) async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'bluetooth_channel',
      'Bluetooth Status',
      channelDescription: 'Shows Bluetooth connection status',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidNotificationDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Bluetooth Status',
      message,
      notificationDetails,
    );
  }

  /// Scan for BLE devices
  /// Scan for BLE devices
Future<void> scanDevices() async {
  if (isScanning.value) return; // Prevent multiple scans

  scanResults.clear();
  isScanning.value = true;

  try {
    await FlutterBluePlus.stopScan(); // Stop any existing scan
    await Future.delayed(const Duration(milliseconds: 500)); // Small delay before starting a new scan

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 5),
      androidUsesFineLocation: true, // ✅ Important for Android 10+
    );

    // ✅ Listen for scan results
    StreamSubscription<List<ScanResult>>? scanSubscription;
    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (results.isNotEmpty) {
        scanResults.assignAll(results);
        print("🔍 Found devices: ${results.map((e) => e.device.name).toList()}");
      }
    });

    await Future.delayed(const Duration(seconds: 5));

    // ✅ Stop scanning after timeout
    await FlutterBluePlus.stopScan();
    await scanSubscription.cancel();
  } catch (e) {
    print("❌ Scan Error: $e");
  } finally {
    isScanning.value = false;
  }
}

  /// Auto-reconnect to device when it is back in range
  void startAutoReconnect() {
    _scanTimer?.cancel(); // Cancel previous timer if any
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!isConnected.value) {
        await scanDevices();
        await Future.delayed(const Duration(seconds: 2)); // Allow scan time

        for (var result in scanResults) {
          if (result.device.id.id == lastConnectedDeviceId) {
            print("Auto-reconnecting to ${result.device.name}");
            await connectToDevice(result.device);
            break;
          }
        }
      }
    });
  }

  /// Connect to a BLE device
  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      connectedDevice = device; // Set the connectedDevice
      isConnected.value = true;

      // Store the device ID for future auto-reconnection
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastConnectedDeviceId', device.id.id);

      // Delay to allow connection to be established
      await Future.delayed(const Duration(milliseconds: 500));
      _setupNotifications(device);  // Setup notifications for receiving data
      _monitorConnectionState(device); // Monitor the connection state

      // Send initial "START" command to the device (optional)
      // await sendData("START");

      // Show connection status notification
      showNotification('Connected to ${device.name}');
    } catch (e) {
      print("Connection Error: $e");
      showNotification('Connection failed');
    }
  }

  /// Monitor connection state
  void _monitorConnectionState(BluetoothDevice device) {
    _connectionSubscription?.cancel();

    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        isConnected.value = true;
        showNotification('Device connected');
      } else {
        isConnected.value = false;
        print("Device disconnected. Auto-reconnect will try again.");
        showNotification('Device disconnected');
      }
    });
  }

  /// Setup notifications for receiving BLE data
  Future<void> _setupNotifications(BluetoothDevice device) async {
    var services = await device.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.notify) {
          await characteristic.setNotifyValue(true);
          characteristic.lastValueStream.listen((value) {
            _handleIncomingData(value);
          });
        }
      }
    }
  }

  /// Handle incoming BLE data
  void _handleIncomingData(List<int> value) {
    // String newData = utf8.decode(value);
    // List<int> intValues = [];
    // intValues.add(value);
    if(onDataReceived == null){
      print("Handle data function is null");
      return;
    }
    onDataReceived!(value);
  }

  /// Disconnect from device
  Future<void> disconnectDevice() async {
    await connectedDevice?.disconnect();
    isConnected.value = false;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastConnectedDeviceId');
    _connectionSubscription?.cancel();
    _scanTimer?.cancel();

    // Show disconnection notification
    showNotification('Disconnected from device');
  }

  /// Forget the last connected device
  Future<void> forgetDevice() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastConnectedDeviceId');
    lastConnectedDeviceId = null;
    print("Device forgotten. Auto-connect disabled.");
    _scanTimer?.cancel();
  }

  /// Set callback for received BLE data
  void setOnDataReceived(Function(List<int>) callback) {
    onDataReceived = callback;
  }

  /// Send data to BLE device
 Future<void> sendData(String data) async {
  if (connectedDevice != null) {
    try {
      var services = await connectedDevice!.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write) {
            // Send the data as a byte array
            await characteristic.write(utf8.encode(data + "\n"));
          }
        }
      }
    } catch (e) {
      print("Data Send Error: $e");
    }
  }
}

  /// Send data to BLE device (write to characteristic)
  Future<void> writeCharacteristic(String data) async {
    if (connectedDevice == null) {
      print("No device connected.");
      return;
    }

    try {
      // Discover the services of the connected device
      var services = await connectedDevice!.discoverServices();

      // Iterate over each service and its characteristics
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          // Check if the characteristic supports the 'write' property
          if (characteristic.properties.write) {
            // Convert the string data to bytes
            List<int> bytes = utf8.encode(data);

            // Write the data to the characteristic
            await characteristic.write(bytes);
            print("Data written to characteristic: $data");

            // Optionally, you can add confirmation logic or notify the user
            showNotification('Data written: $data');
            return; // Exit once data is written
          }
        }
      }
      print("No writable characteristic found.");
    } catch (e) {
      print("Error while writing to characteristic: $e");
      showNotification('Error while writing data');
    }
  }

  @override
  void onClose() {
    _connectionSubscription?.cancel();
    _scanTimer?.cancel();
    super.onClose();
  }
}

/// Device data model to handle device information and preferences
class DeviceData {
  String? deviceName;
  String? deviceId;
  bool isConnected;
  String? lastConnectedDeviceId;

  DeviceData({
    this.deviceName,
    this.deviceId,
    this.isConnected = false,
    this.lastConnectedDeviceId,
  });

  /// Create a device data from the connected Bluetooth device
  factory DeviceData.fromDevice(BluetoothDevice device, bool isConnected) {
    return DeviceData(
      deviceName: device.name,
      deviceId: device.id.id,
      isConnected: isConnected,
    );
  }

  /// Save the device data to SharedPreferences (optional)
  Future<void> saveToPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('deviceName', deviceName ?? "");
    await prefs.setString('deviceId', deviceId ?? "");
    await prefs.setBool('isConnected', isConnected);
  }

  /// Load device data from SharedPreferences (optional)
  static Future<DeviceData?> loadFromPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? deviceName = prefs.getString('deviceName');
    String? deviceId = prefs.getString('deviceId');
    bool isConnected = prefs.getBool('isConnected') ?? false;

    if (deviceName != null && deviceId != null) {
      return DeviceData(
        deviceName: deviceName,
        deviceId: deviceId,
        isConnected: isConnected,
      );
    }
    return null;
  }
}
