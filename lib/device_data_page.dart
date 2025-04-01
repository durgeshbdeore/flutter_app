//import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'ble_controller.dart';  // Ensure this is correctly imported

class DeviceDataPage extends StatefulWidget {
  const DeviceDataPage({super.key});

  @override
  _DeviceDataPageState createState() => _DeviceDataPageState();
}

class _DeviceDataPageState extends State<DeviceDataPage> {
  final BleController controller = Get.find<BleController>();
  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  List<String> terminalLogs = [];
  String? savedFilePath;
  String dataFormat = "Hex"; // Default data format

  @override
  void initState() {
    super.initState();

    // Ensure the BLE controller has this method to handle incoming data.
    controller.setOnDataReceived((List<int> data) {
      setState(() {
        terminalLogs.add("Received: $data");
        scrollToBottom();
      });
    });

    Future.delayed(Duration.zero, () {
      controller.scanDevices(); // Assuming you want to start scanning devices on page load
    });
  }

  void scrollToBottom() {
    Future.delayed(Duration(milliseconds: 300), () {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });
  }

  void getData(List<int> data) {
    setState(() {
      terminalLogs.add("Received: $data");
      scrollToBottom();
    });
  }

  // Method to save logs to a file
  Future<void> saveToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/heart_rate_data.txt');
      await file.writeAsString(terminalLogs.join("\n"));

      setState(() {
        savedFilePath = file.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File saved: ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save file: $e')),
      );
    }
  }

  // Method to open the saved file
  void openFile() {
    if (savedFilePath != null) {
      OpenFilex.open(savedFilePath!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No file found. Save data first.')),
      );
    }
  }

  // Method to send a command to the BLE device
 void sendCommand() {
  String command = inputController.text.trim();
  if (command.isNotEmpty) {
    // Send the command as a string (controller.sendData will handle encoding)
    controller.sendData(command);
    setState(() {
      terminalLogs.add("Sent: $command");
      inputController.clear();
      scrollToBottom();
    });
  }
}

  // Method to listen for incoming data from the BLE device
  Future<void> listenForData() async {
    // Assuming your controller has a method to listen for data
    controller.setOnDataReceived((List<int> data) {
      getData(data);
    });

    // Optionally, you can subscribe to characteristic notifications for real-time data
    //await controller.subscribeToNotifications();  // Ensure this is implemented in the BleController
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Device Data"),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ["Hex", "Int", "Raw"].map((format) {
              return ElevatedButton(
                onPressed: () {
                  setState(() {
                    dataFormat = format;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: dataFormat == format ? Colors.blue : Colors.grey,
                ),
                child: Text(format),
              );
            }).toList(),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: terminalLogs.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(terminalLogs[index]));
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    decoration: InputDecoration(labelText: "Enter command"),
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(onPressed: sendCommand, child: Text("Send")),
              ],
            ),
          ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(onPressed: saveToFile, child: Text("Download File")),
              SizedBox(width: 10),
              ElevatedButton(onPressed: openFile, child: Text("Open File")),
            ],
          ),
          SizedBox(height: 10),
        ],
      ),
    );
  }
}
