import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothHomePage extends StatefulWidget {
  const BluetoothHomePage({super.key});

  @override
  State<BluetoothHomePage> createState() => _BluetoothHomePageState();
}

class _BluetoothHomePageState extends State<BluetoothHomePage> {
  BluetoothDevice? esp32;
  BluetoothCharacteristic? ledChar;
  StreamSubscription<BluetoothConnectionState>? _stateSubscription;

  final String serviceUUID = "12345678-1234-1234-1234-123456789012";
  final String charUUID = "87654321-4321-4321-4321-210987654321";

  bool isConnected = false;
  bool isScanning = false;
  bool hasPermissions = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  @override
  void dispose() {
    _disconnectDevice();
    _stateSubscription?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initBluetooth() async {
    // Initialize FlutterBluePlus
    await FlutterBluePlus.adapterState.first;
    requestPermissions();
  }

  // Request Bluetooth & Location permissions
  void requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetooth,
      Permission.locationWhenInUse,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (allGranted) {
      setState(() => hasPermissions = true);
      print("All permissions granted");
    } else {
      print("Bluetooth/Location permissions denied!");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Permissions required for Bluetooth"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Start scanning for ESP32
  void startScan() async {
    if (isScanning || !hasPermissions) return;
    
    try {
      setState(() => isScanning = true);
      
      // Stop any ongoing scan
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      // Start scan with specific parameters
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );

      // Listen to scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          print("Found device: ${r.device.name} - ${r.device.remoteId}");
          if (r.device.name == "ESP32_LED") {
            esp32 = r.device;
            await FlutterBluePlus.stopScan();
            _scanSubscription?.cancel();
            if (mounted) {
              setState(() => isScanning = false);
            }
            await connectToESP32();
            break;
          }
        }
      });
    } catch (e) {
      print("Scan error: $e");
      if (mounted) {
        setState(() => isScanning = false);
      }
    }
  }

  // Connect to ESP32
  Future<void> connectToESP32() async {
    if (esp32 == null) return;

    try {
      // Listen to connection state BEFORE connecting
      _stateSubscription = esp32!.connectionState.listen((state) {
        print("Connection state: $state");
        if (mounted) {
          setState(() {
            isConnected = state == BluetoothConnectionState.connected;
          });
        }
        
        if (state == BluetoothConnectionState.connected) {
          discoverServices();
        } else if (state == BluetoothConnectionState.disconnected) {
          ledChar = null;
        }
      });

      // Connect WITHOUT autoConnect and WITHOUT mtu parameter
      await esp32!.connect(
        autoConnect: false, // Changed from true to false
        timeout: const Duration(seconds: 15),
      ).catchError((e) {
        print("Connection failed: $e");
        if (mounted) {
          setState(() => isConnected = false);
        }
      });

    } catch (e) {
      print("Connect error: $e");
      if (mounted) {
        setState(() => isConnected = false);
      }
    }
  }

  // Discover LED characteristic
  Future<void> discoverServices() async {
    if (esp32 == null || !isConnected) return;

    try {
      List<BluetoothService> services = await esp32!.discoverServices();
      print("Found ${services.length} services");
      
      for (var service in services) {
        print("Service: ${service.uuid}");
        if (service.uuid.toString() == serviceUUID) {
          print("Found target service!");
          for (var c in service.characteristics) {
            print("Characteristic: ${c.uuid}");
            if (c.uuid.toString() == charUUID) {
              ledChar = c;
              print("LED characteristic found!");
              break;
            }
          }
        }
      }
      
      if (ledChar == null) {
        print("LED characteristic NOT found!");
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("Service discovery error: $e");
    }
  }

  // LED ON with better error handling
  Future<void> ledOn() async {
    if (ledChar == null || !isConnected) {
      print("Cannot send LED ON - no characteristic or disconnected");
      _showError("Not connected to ESP32");
      return;
    }

    try {
      await ledChar!.write("1".codeUnits, withoutResponse: false);
      print("LED ON sent successfully");
    } catch (e) {
      print("Error sending LED ON: $e");
      _showError("Failed to turn LED ON");
      if (mounted) {
        setState(() => isConnected = false);
      }
    }
  }

  // LED OFF with better error handling
  Future<void> ledOff() async {
    if (ledChar == null || !isConnected) {
      print("Cannot send LED OFF - no characteristic or disconnected");
      _showError("Not connected to ESP32");
      return;
    }

    try {
      await ledChar!.write("0".codeUnits, withoutResponse: false);
      print("LED OFF sent successfully");
    } catch (e) {
      print("Error sending LED OFF: $e");
      _showError("Failed to turn LED OFF");
      if (mounted) {
        setState(() => isConnected = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Disconnect from device
  Future<void> _disconnectDevice() async {
    if (esp32 != null) {
      try {
        await esp32!.disconnect();
      } catch (e) {
        print("Disconnect error: $e");
      }
    }
    ledChar = null;
    _stateSubscription?.cancel();
    if (mounted) {
      setState(() {
        isConnected = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 LED Control"),
        actions: [
          if (isConnected)
            IconButton(
              icon: Icon(Icons.bluetooth_disabled),
              onPressed: _disconnectDevice,
              tooltip: "Disconnect",
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Connection Status
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isConnected ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      isConnected 
                          ? "ESP32 Connected" 
                          : isScanning
                              ? "Scanning for ESP32..."
                              : "Disconnected",
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 40),
              
              // LED Control Buttons
              Text(
                "LED Control",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: isConnected ? ledOn : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    ),
                    child: Text(
                      "LED ON",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: isConnected ? ledOff : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    ),
                    child: Text(
                      "LED OFF",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: 40),
              
              // Connection Button
              ElevatedButton(
                onPressed: !isConnected && !isScanning ? startScan : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bluetooth_searching),
                    SizedBox(width: 10),
                    Text(
                      isScanning ? "Scanning..." : "Connect to ESP32",
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20),
              
              // Permission status
              if (!hasPermissions)
                Text(
                  "Bluetooth permissions required!",
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
        ),
      ),
    );
  }
}