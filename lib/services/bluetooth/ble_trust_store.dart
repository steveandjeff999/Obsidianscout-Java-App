/// Devices this install trusts for Bluetooth transfer, and this install's own Bluetooth identity.
///
/// After one transfer verified with a code, both devices keep a shared 256-bit pairing key, so later transfers
/// between them skip the code. Keys live in the platform's secure storage (Keychain / Keystore / DPAPI).
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ble_transfer_protocol.dart';
import 'spake2.dart' show bytesToHex, hexToBytes;

/// Where trust records are kept. Swappable so tests don't need a platform keychain.
abstract class BleSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class _PlatformSecretStorage implements BleSecretStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

class MemorySecretStorage implements BleSecretStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class BleTrustStore {
  static const String _key = 'obsidianscout:ble_trust_v1';
  static const int maxPeers = 64;

  static BleSecretStorage _storage = _PlatformSecretStorage();
  static BleSecretStorage get storage => _storage;

  /// Swaps the backend (tests). Also starts a fresh operation queue.
  static set storage(BleSecretStorage value) {
    _storage = value;
    _lock = Future<void>.value();
  }

  static Future<void> _lock = Future<void>.value();

  /// Runs read-modify-write steps one at a time.
  static Future<T> _serial<T>(Future<T> Function() op) {
    final next = _lock.then((_) => op());
    _lock = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<Map<String, dynamic>> _load() async {
    try {
      final raw = await storage.read(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (e) {
      debugPrint('BLE trust store unreadable, starting fresh: $e');
    }
    return <String, dynamic>{};
  }

  static Future<void> _store(Map<String, dynamic> data) => storage.write(_key, jsonEncode(data));

  static Future<BleIdentity> identity() => _serial(() async {
        final data = await _load();
        var idHex = data['deviceId'] as String?;
        var beaconHex = data['beaconKey'] as String?;
        if (idHex == null || idHex.length != 32 || beaconHex == null || beaconHex.length != 64) {
          final r = Random.secure();
          if (idHex == null || idHex.length != 32) idHex = bytesToHex(List<int>.generate(16, (_) => r.nextInt(256)));
          beaconHex = bytesToHex(List<int>.generate(32, (_) => r.nextInt(256)));
          data['deviceId'] = idHex;
          data['beaconKey'] = beaconHex;
          await _store(data);
        }
        return BleIdentity(id: hexToBytes(idHex), name: _deviceName(idHex), beaconKey: hexToBytes(beaconHex));
      });

  static Future<List<BleTrustedPeer>> peers(BleTrustRole role) async {
    final data = await _serial(_load);
    return _peers(data).where((p) => p.role == role).toList()..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
  }

  /// Adds or replaces the record for this peer and role.
  static Future<void> save(BleTrustedPeer peer) => _serial(() async {
        final data = await _load();
        final list = _peers(data).where((p) => !(p.id == peer.id && p.role == peer.role)).toList()..add(peer);
        list.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        data['peers'] = list.take(maxPeers).map((p) => p.toJson()).toList();
        await _store(data);
      });

  static Future<void> remove(String id, BleTrustRole role) => _serial(() async {
        final data = await _load();
        data['peers'] = _peers(data).where((p) => !(p.id == id && p.role == role)).map((p) => p.toJson()).toList();
        await _store(data);
      });

  static List<BleTrustedPeer> _peers(Map<String, dynamic> data) {
    final raw = data['peers'];
    if (raw is! List) return [];
    return raw.map(BleTrustedPeer.fromJson).whereType<BleTrustedPeer>().toList();
  }

  /// A label the other side shows for this device: the computer name where there is one, otherwise the platform
  /// plus the start of the device id.
  static String _deviceName(String idHex) {
    final short = idHex.substring(0, 4).toUpperCase();
    if (kIsWeb) return 'Device $short';
    try {
      final host = Platform.localHostname.trim();
      if (host.isNotEmpty && host.toLowerCase() != 'localhost') {
        return host.length > 40 ? host.substring(0, 40) : host;
      }
    } catch (_) {}
    final os = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
            ? 'iPhone'
            : Platform.isMacOS
                ? 'Mac'
                : Platform.isWindows
                    ? 'Windows PC'
                    : 'Device';
    return '$os $short';
  }
}
