// In-memory stand-ins for the universal_ble platforms, shared by the Bluetooth transfer tests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_transfer_protocol.dart';
import 'package:universal_ble/universal_ble.dart';
// ignore: implementation_imports
import 'package:universal_ble/src/universal_ble.g.dart' show PeripheralService;

const fakePhoneId = 'aa:bb:cc:dd:ee:01';
const fakeReceiverId = 'aa:bb:cc:dd:ee:99';

/// Everything that went over the air, as an eavesdropper would capture it.
final List<int> airCapture = [];

class FakePeripheral extends UniversalBlePeripheralUnsupported {
  OnPeripheralReadRequest? read;
  OnPeripheralWriteRequest? write;
  final List<String> services = [];
  List<String> advertised = [];

  bool get advertising => advertised.isNotEmpty;

  @override
  Future<BlePeripheralCapabilities> getCapabilities() async => const BlePeripheralCapabilities(
        supportsPeripheralMode: true,
        supportsManufacturerDataInAdvertisement: true,
        supportsManufacturerDataInScanResponse: true,
        supportsServiceDataInAdvertisement: true,
        supportsServiceDataInScanResponse: true,
        supportsTargetedCharacteristicUpdate: true,
        supportsAdvertisingTimeout: false,
      );

  @override
  Future<PeripheralReadinessState> getAvailabilityState() async => PeripheralReadinessState.ready;

  @override
  Future<void> addService(PeripheralService service, {bool primary = true, Duration? timeout}) async =>
      services.add(service.uuid.toLowerCase());

  @override
  Future<void> clearServices() async => services.clear();

  @override
  Future<void> startAdvertising({
    required List<String> services,
    String? localName,
    Duration? timeout,
    ManufacturerData? manufacturerData,
    PeripheralPlatformConfig? platformConfig,
  }) async =>
      advertised = List.of(services);

  @override
  Future<void> stopAdvertising() async => advertised = [];

  @override
  void setReadRequestHandler(OnPeripheralReadRequest? handler) => read = handler;

  @override
  void setWriteRequestHandler(OnPeripheralWriteRequest? handler) => write = handler;
}

class FakeCentral extends UniversalBlePlatform {
  FakeCentral(this.phone);
  final FakePeripheral phone;
  final int mtu = 64;

  /// Extra stale addresses the phone is also seen under (Android address rotation). Connecting to one fails.
  final List<String> staleAddresses = [];
  final List<String> connectAttempts = [];
  bool clearGattCacheRequested = false;

  void _requireService(String service) {
    if (!phone.services.contains(service.toLowerCase()) || phone.read == null || phone.write == null) {
      throw UniversalBleException(code: UniversalBleErrorCode.failed, message: 'service gone');
    }
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async => AvailabilityState.poweredOn;
  @override
  Future<bool> enableBluetooth() async => true;
  @override
  Future<bool> disableBluetooth() async => false;
  @override
  Future<void> startScan({ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    if (phone.advertising) {
      for (final stale in staleAddresses) {
        updateScanResult(BleDevice(deviceId: stale, name: null, rssi: -70, services: phone.advertised));
      }
      updateScanResult(BleDevice(deviceId: fakePhoneId, name: 'Pixel', rssi: -50, services: phone.advertised));
    }
  }

  @override
  Future<void> stopScan() async {}
  @override
  Future<bool> isScanning() async => false;
  @override
  Future<void> connect(String deviceId,
      {Duration? connectionTimeout, bool autoConnect = false, ConnectionPlatformConfig? platformConfig}) async {
    connectAttempts.add(deviceId);
    if (staleAddresses.contains(deviceId)) {
      scheduleMicrotask(() => updateConnection(deviceId, false, 'unreachable'));
      return;
    }
    scheduleMicrotask(() => updateConnection(deviceId, true));
  }

  @override
  Future<void> disconnect(String deviceId) async => scheduleMicrotask(() => updateConnection(deviceId, false));
  @override
  Future<List<BleService>> discoverServices(String deviceId, bool withDescriptors,
          {DiscoverServicesPlatformConfig? platformConfig}) async {
    clearGattCacheRequested = platformConfig?.android?.clearGattCache ?? false;
    return phone.services.map((uuid) => BleService(uuid, const [])).toList();
  }
  @override
  Future<void> setNotifiable(String deviceId, String service, String characteristic, BleInputProperty p) async {}
  @override
  Future<Uint8List> readValue(String deviceId, String service, String characteristic, {Duration? timeout}) async {
    _requireService(service);
    final result = phone.read!(fakeReceiverId, characteristic.toLowerCase(), 0, null);
    final value = result?.value ?? Uint8List(0);
    expect(value.length, lessThanOrEqualTo(mtu - 1), reason: 'a read must fit one ATT response');
    airCapture.addAll(value);
    return value;
  }

  @override
  Future<Uint8List> readDescriptorValue(String d, String s, String c, String desc, {Duration? timeout}) async =>
      Uint8List(0);
  @override
  Future<void> writeValue(String deviceId, String service, String characteristic, Uint8List value,
      BleOutputProperty bleOutputProperty) async {
    _requireService(service);
    expect(value.length, lessThanOrEqualTo(mtu - 3), reason: 'a write must fit one ATT request');
    airCapture.addAll(value);
    phone.write!(fakeReceiverId, characteristic.toLowerCase(), 0, value);
  }

  @override
  Future<void> writeDescriptorValue(String d, String s, String c, String desc, Uint8List v) async {}
  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async => mtu;
  @override
  Future<int> readRssi(String deviceId) async => -50;
  @override
  Future<void> requestConnectionPriority(String deviceId, BleConnectionPriority priority) async {}
  @override
  Future<bool> isPaired(String deviceId) async => false;
  @override
  Future<bool> pair(String deviceId) async => false;
  @override
  Future<void> unpair(String deviceId) async {}
  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async => BleConnectionState.connected;
  @override
  Future<List<BleDevice>> getSystemDevices(List<String>? withServices) async => [];
}

BleTransferPayload samplePayload() {
  final json = jsonEncode({
    'type': 'pit-scout',
    'data': {'targetTeamNumber': 9001, 'eventKey': '2026demo', 'drivetrain': 'swerve', 'notes': 'n' * 2000},
  });
  return BleTransferPayload(compressed: Uint8List.fromList(zlib.encode(utf8.encode(json))), summary: 'Pit - Team 9001');
}

String wrongCodeFor(String code) => code == '000000' ? '111111' : '000000';
