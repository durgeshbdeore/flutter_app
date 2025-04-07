import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'ble_controller.dart';
import 'device_data_page.dart';
import 'background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService(); // Start background BLE & reconnection logic
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final BleController controller = Get.put(BleController());

  @override
  void initState() {
    super.initState();
    controller.initializeBluetooth();

    // Attempt auto-reconnect in background too
    controller.startAutoReconnect();

    // Navigate on connection
    ever(controller.isConnected, (connected) {
      if (connected == true) {
        Get.off(() => const DeviceDataPage());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE Scanner")),
      body: Obx(() {
        return Column(
          children: [
            const SizedBox(height: 20),
            Text(
              controller.isConnected.value
                  ? "✅ Connected to ${controller.connectedDevice?.name ?? 'Unknown Device'}"
                  : "❌ Not Connected",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: controller.isConnected.value ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: controller.scanResults.isNotEmpty
                  ? ListView.builder(
                      itemCount: controller.scanResults.length,
                      itemBuilder: (context, index) {
                        final result = controller.scanResults[index];
                        return Card(
                          child: ListTile(
                            title: Text(result.device.name.isNotEmpty
                                ? result.device.name
                                : "Unnamed Device (${result.device.id.id})"),
                            subtitle: Text(result.device.id.id),
                            trailing: ElevatedButton(
                              onPressed: () async {
                                await controller.connectToDevice(result.device);
                              },
                              child: const Text("CONNECT"),
                            ),
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Text("No devices found.\nPress SCAN to start scanning.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ),
            ),
            const SizedBox(height: 10),
            if (controller.isConnected.value)
              ElevatedButton(
                onPressed: controller.disconnectDevice,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("DISCONNECT", style: TextStyle(color: Colors.white)),
              ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: controller.scanDevices,
              child: const Text("SCAN"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: controller.forgetDevice,
              child: const Text("FORGET DEVICE"),
            ),
            const SizedBox(height: 20),
          ],
        );
      }),
    );
  }
}
