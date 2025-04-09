import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'ble_controller.dart';

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

    // Set data received callback
    controller.setOnDataReceived((List<int> data) {
      setState(() {
        String formattedData = formatData(data);
        terminalLogs.add("Received: $formattedData");
        scrollToBottom();
      });
    });
  }

  String formatData(List<int> data) {
    switch (dataFormat) {
      case "Hex":
        return data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
      case "Int":
        return data.join(', ');
      case "Raw":
        return String.fromCharCodes(data);
      default:
        return data.toString();
    }
  }

  void scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> saveToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/ble_data.txt');
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

  void openFile() {
    if (savedFilePath != null) {
      OpenFilex.open(savedFilePath!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file found. Save data first.')),
      );
    }
  }

  void sendCommand() {
    String command = inputController.text.trim();
    if (command.isNotEmpty) {
      controller.writeCharacteristic(command);
      setState(() {
        terminalLogs.add("Sent: $command");
        inputController.clear();
        scrollToBottom();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Device Data"),
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
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    decoration: const InputDecoration(labelText: "Enter command"),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: sendCommand, child: const Text("Send")),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(onPressed: saveToFile, child: const Text("Download File")),
              const SizedBox(width: 10),
              ElevatedButton(onPressed: openFile, child: const Text("Open File")),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}