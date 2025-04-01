import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'ble_controller.dart';
import 'device_data_page.dart';  // Ensure this import is correct.

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'BLE Heart Rate Monitor',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
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

    // Attempt to auto-reconnect after a short delay
    Future.delayed(const Duration(seconds: 1), () {
      controller.startAutoReconnect();
    });

    // Navigate to DeviceDataPage if connected
    ever(controller.isConnected, (connected) {
      if (connected == true) {
        Get.off(() => const DeviceDataPage()); // Using the correct class here
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
              child: ListView.builder(
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
              ),
            ),
            if (controller.isConnected.value)
              ElevatedButton(
                onPressed: () => controller.disconnectDevice(),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("DISCONNECT", style: TextStyle(color: Colors.white)),
              ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => controller.scanDevices(),
              child: const Text("SCAN"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await controller.forgetDevice();
              },
              child: const Text("FORGET DEVICE"),
            ),
          ],
        );
      }),
    );
  }
}
