import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<bool> onStart(ServiceInstance service) async {
  // Initialize BLE and Notifications
  FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('app_icon');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await notificationsPlugin.initialize(initializationSettings);

  // Show foreground notification when running
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: "BLE Service Running",
      content: "Scanning for devices...",
    );
  }

  FlutterBluePlus.setLogLevel(LogLevel.verbose);

  // Auto-reconnect loop
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    bool isScanning = (await FlutterBluePlus.isScanning) as bool; // Fixing the negation error
    if (!isScanning) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    }
  });

  // Listen for BLE scan results
  FlutterBluePlus.scanResults.listen((results) {
    for (var result in results) {
      print("Found device: ${result.device.name}");
    }
  });

  return true; // Fixing the return type issue
}

/// Start the background service
Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart, // Function must return Future<bool>
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onStart,
    ),
  );
}
