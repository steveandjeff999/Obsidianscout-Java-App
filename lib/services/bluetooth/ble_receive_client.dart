/// Receiver side of Bluetooth transfer: finds scout phones that are sending, then pulls an entry from the one the
/// user picks: straight away if the phone is trusted, otherwise with the code shown on that phone.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_transfer_protocol.dart';
import 'ble_trust_store.dart';

/// One sending phone, identified by the tag it shows. Android rotates the random address a phone advertises
/// from, so the same phone can briefly appear under two addresses; they are grouped here, newest first.
class BleNearbyScout {
  final String tag;
  final String hint;
  final List<String> deviceIds;
  final String? name;
  final int? rssi;
  final DateTime lastSeen;

  /// Set when this phone is one this receiver is paired with.
  final BleTrustedPeer? trustedPeer;

  const BleNearbyScout({
    required this.tag,
    required this.deviceIds,
    required this.lastSeen,
    this.hint = '000000000000',
    this.name,
    this.rssi,
    this.trustedPeer,
  });

  String get deviceId => deviceIds.first;
  String get serviceUuid => BleTransferProtocol.serviceUuid(tag, hint);
}

class _Sighting {
  final String deviceId;
  final String tag;
  final String hint;
  final String? name;
  final int? rssi;
  final DateTime seen;
  const _Sighting(this.deviceId, this.tag, this.hint, this.name, this.rssi, this.seen);
}

enum BleReceiveFailure { wrongCode, busy, locked, connect, timeout, protocol, tooLarge, unavailable, cancelled }

class BleReceiveException implements Exception {
  final BleReceiveFailure failure;
  final String message;
  const BleReceiveException(this.failure, this.message);
  @override
  String toString() => message;
}

enum BleReceiveStage { connecting, verifying, waitingForCode, receiving, importing }

/// The code the user typed, and whether to trust the phone for next time.
typedef BleCodeAnswer = ({String code, bool trust});

class BleReceiveOutcome {
  final BleTransferResult result;

  /// The phone was trusted, so no code was needed.
  final bool viaTrust;

  /// This transfer paired the phone for next time.
  final bool newlyTrusted;

  /// "Device - username" of the sender, when it said.
  final String? senderLabel;

  const BleReceiveOutcome({required this.result, this.viaTrust = false, this.newlyTrusted = false, this.senderLabel});
}

class BleReceiveClient {
  BleReceiveClient({this.username});

  /// Signed-in username, shown to phones this receiver pairs with.
  final String? username;

  /// Phones not heard from in this long drop off the list.
  static const Duration staleAfter = Duration(seconds: 8);
  static const Duration transferTimeout = Duration(seconds: 25);
  static const Duration _pollInterval = Duration(milliseconds: 30);

  /// Android to Android service discovery can take several seconds on a busy radio.
  static const Duration _discoveryTimeout = Duration(seconds: 25);

  final ValueNotifier<List<BleNearbyScout>> scouts = ValueNotifier(const []);

  /// Phones this receiver may pull from without a code.
  final ValueNotifier<List<BleTrustedPeer>> trustedScouts = ValueNotifier(const []);

  final Map<String, _Sighting> _seen = {};
  StreamSubscription<BleDevice>? _scanSub;
  Timer? _pruneTimer;
  bool _scanning = false;
  bool _busy = false;
  bool _disposed = false;
  BleIdentity? _identity;

  static bool get platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Null when ready, or a sentence explaining what the user needs to fix.
  static Future<String?> checkReady() async {
    if (!platformSupported) return 'Bluetooth receiving is not supported on this device.';
    try {
      if (!kIsWeb && Platform.isAndroid) {
        // Covers both Android 12+ (scan/connect) and older versions (location, needed to scan there).
        try {
          await UniversalBle.requestPermissions();
        } catch (_) {
          return 'Allow Bluetooth access for ObsidianScout to receive entries.';
        }
      }
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      switch (availability) {
        case AvailabilityState.poweredOn:
        case AvailabilityState.unknown:
        case AvailabilityState.resetting:
          return null;
        case AvailabilityState.poweredOff:
          return 'Turn on Bluetooth to receive entries.';
        case AvailabilityState.unauthorized:
          return 'Allow Bluetooth access for ObsidianScout to receive entries.';
        case AvailabilityState.unsupported:
          return 'This device has no usable Bluetooth adapter.';
      }
    } catch (e) {
      return 'Could not check Bluetooth: $e';
    }
  }

  Future<BleIdentity> _ensureIdentity() async =>
      _identity ??= (await BleTrustStore.identity()).withUsername(username);

  Future<void> reloadTrusted() async {
    final peers = await BleTrustStore.peers(BleTrustRole.scout);
    if (_disposed) return;
    trustedScouts.value = peers;
    _publish();
  }

  /// Stops trusting a phone; it will need its code again.
  Future<void> forgetScout(String id) async {
    await BleTrustStore.remove(id, BleTrustRole.scout);
    await reloadTrusted();
  }

  Future<void> startScan() async {
    if (_scanning || _disposed) return;
    _scanning = true;
    await reloadTrusted();
    _scanSub ??= UniversalBle.scanStream.listen(_onScanResult);
    _pruneTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _prune());
    try {
      // No service filter: each phone advertises its own UUID, so we match on the shared prefix instead.
      await UniversalBle.startScan(
        platformConfig: PlatformConfig(
          android: AndroidOptions(requestLocationPermission: false, scanMode: AndroidScanMode.lowLatency),
        ),
      );
    } catch (e) {
      _scanning = false;
      rethrow;
    }
  }

  Future<void> stopScan() async {
    if (!_scanning) return;
    _scanning = false;
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _disposed = true;
    scouts.dispose();
    trustedScouts.dispose();
  }

  void _onScanResult(BleDevice device) {
    ({String tag, String hint})? parsed;
    for (final uuid in device.services) {
      parsed = BleTransferProtocol.parseServiceUuid(uuid);
      if (parsed != null) break;
    }
    if (parsed == null) return;
    final name = (device.name ?? '').trim();
    _seen[device.deviceId] =
        _Sighting(device.deviceId, parsed.tag, parsed.hint, name.isEmpty ? null : name, device.rssi, DateTime.now());
    _publish();
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(staleAfter);
    final before = _seen.length;
    _seen.removeWhere((_, s) => s.seen.isBefore(cutoff));
    if (_seen.length != before) _publish();
  }

  BleTrustedPeer? _matchTrusted(String tag, String hint) {
    for (final peer in trustedScouts.value) {
      final key = peer.beaconKey;
      if (key != null && BleTransferProtocol.beaconHint(key, tag) == hint) return peer;
    }
    return null;
  }

  void _publish() {
    if (_disposed) return;
    final byPhone = <String, List<_Sighting>>{};
    for (final s in _seen.values) {
      byPhone.putIfAbsent('${s.tag}-${s.hint}', () => []).add(s);
    }
    final list = byPhone.values.map((sightings) {
      sightings.sort((a, b) => b.seen.compareTo(a.seen));
      final first = sightings.first;
      final rssis = sightings.map((s) => s.rssi).whereType<int>();
      return BleNearbyScout(
        tag: first.tag,
        hint: first.hint,
        deviceIds: sightings.map((s) => s.deviceId).toList(),
        name: sightings.map((s) => s.name).firstWhere((n) => n != null, orElse: () => null),
        rssi: rssis.isEmpty ? null : rssis.reduce((a, b) => a > b ? a : b),
        lastSeen: first.seen,
        trustedPeer: _matchTrusted(first.tag, first.hint),
      );
    }).toList()
      // Trusted phones first, then by signal.
      ..sort((a, b) {
        if ((a.trustedPeer != null) != (b.trustedPeer != null)) return a.trustedPeer != null ? -1 : 1;
        return (b.rssi ?? -999).compareTo(a.rssi ?? -999);
      });
    scouts.value = list;
  }

  /// Connects and discovers services, trying each address the phone was seen under (newest first). Returns the
  /// address that worked.
  Future<String> _connect(BleNearbyScout scout) async {
    final service = scout.serviceUuid;
    Object? lastError;
    for (final deviceId in scout.deviceIds.take(3)) {
      try {
        await UniversalBle.connect(
          deviceId,
          timeout: const Duration(seconds: 15),
          platformConfig: ConnectionPlatformConfig(android: AndroidConnectionOptions(closeGattOnDetach: true)),
        );
        final services = await UniversalBle.discoverServices(
          deviceId,
          timeout: _discoveryTimeout,
          // Each send session registers a new service, so a cached layout from an earlier session is wrong.
          platformConfig: DiscoverServicesPlatformConfig(android: AndroidDiscoverServicesOptions(clearGattCache: true)),
        );
        if (!services.any((s) => s.uuid.toLowerCase() == service)) {
          throw StateError('service $service not found among ${services.map((s) => s.uuid).join(', ')}');
        }
        return deviceId;
      } catch (e) {
        lastError = e;
        debugPrint('BLE connect to $deviceId (phone ${scout.tag}) failed: $e');
        try {
          await UniversalBle.disconnect(deviceId);
        } catch (_) {}
      }
    }
    if (lastError is StateError) {
      throw BleReceiveException(BleReceiveFailure.connect,
          'Phone ${scout.tag} is no longer sending. Ask the scout to reopen Send over Bluetooth.');
    }
    throw BleReceiveException(
        BleReceiveFailure.connect, 'Could not connect to phone ${scout.tag}. Move closer and try again.');
  }

  /// Pulls the entry from [scout]: through trust if the phone is paired, otherwise with the code [askCode]
  /// returns (asked only when needed, while connected). Hands the entry to [importer] and reports the result back
  /// to the phone. Throws [BleReceiveException] on failure; nothing reaches [importer] unless the phone proved it
  /// knew the code or the pairing key.
  Future<BleReceiveOutcome> receive(
    BleNearbyScout scout, {
    required Future<BleCodeAnswer?> Function() askCode,
    required Future<BleTransferResult> Function(BleTransferPayload payload) importer,
    void Function(BleReceiveStage stage)? onStage,
  }) async {
    if (_busy) throw const BleReceiveException(BleReceiveFailure.busy, 'Already receiving from a phone.');
    _busy = true;
    final wasScanning = _scanning;
    String? deviceId;
    final service = scout.serviceUuid;
    try {
      final identity = await _ensureIdentity();
      await stopScan();
      onStage?.call(BleReceiveStage.connecting);
      deviceId = await _connect(scout);
      final device = deviceId;

      int mtu = 23;
      try {
        mtu = await UniversalBle.requestMtu(device, 517);
      } catch (_) {}
      mtu = mtu.clamp(23, 517);

      // One writer/reader per connection: a fallback from trust to the code continues the same frame sequence.
      final writer = FrameWriter();
      final reader = FrameReader();

      Future<void> send(Uint8List message) async {
        for (final frame in writer.split(message, mtu - 3)) {
          await UniversalBle.write(device, service, BleTransferProtocol.rxUuid, frame);
        }
      }

      Future<Uint8List> nextMessage(DateTime deadline) async {
        while (true) {
          if (DateTime.now().isAfter(deadline)) {
            throw const BleReceiveException(BleReceiveFailure.timeout, 'The phone stopped responding. Try again.');
          }
          final value = await UniversalBle.read(device, service, BleTransferProtocol.txUuid);
          if (value.isEmpty) {
            await Future<void>.delayed(_pollInterval);
            continue;
          }
          final message = reader.add(value);
          if (message != null) return message;
        }
      }

      Future<void> run(ReceiverSession session) async {
        final deadline = DateTime.now().add(transferTimeout);
        onStage?.call(BleReceiveStage.verifying);
        await send(session.hello());
        while (session.stage == ReceiverSessionStage.waitingChallenge ||
            session.stage == ReceiverSessionStage.waitingData) {
          final incoming = await nextMessage(deadline);
          for (final reply in session.handle(incoming)) {
            await send(reply);
          }
          if (session.stage == ReceiverSessionStage.waitingData) onStage?.call(BleReceiveStage.receiving);
        }
      }

      ReceiverSession? session;
      final peer = scout.trustedPeer;
      if (peer != null) {
        final trusted = ReceiverSession.trusted(tag: scout.tag, mtu: mtu, identity: identity, expectedPeer: peer);
        await run(trusted);
        if (trusted.stage == ReceiverSessionStage.finished) {
          session = trusted;
        } else if (trusted.failure != BleTransferError.notTrusted) {
          throw _failureFor(trusted.failure ?? BleTransferError.protocol, scout.tag);
        } else {
          // The phone no longer trusts this receiver (forgotten there, or re-paired). Use the code instead.
          debugPrint('BLE phone ${scout.tag} no longer trusts this receiver; asking for the code');
        }
      }

      if (session == null) {
        onStage?.call(BleReceiveStage.waitingForCode);
        final answer = await askCode();
        if (answer == null) {
          throw const BleReceiveException(BleReceiveFailure.cancelled, 'Cancelled.');
        }
        final coded = ReceiverSession.code(
          tag: scout.tag,
          code: answer.code,
          mtu: mtu,
          identity: identity,
          requestTrust: answer.trust,
        );
        await run(coded);
        if (coded.stage != ReceiverSessionStage.finished) {
          throw _failureFor(coded.failure ?? BleTransferError.protocol, scout.tag);
        }
        session = coded;
      }

      onStage?.call(BleReceiveStage.importing);
      BleTransferResult result;
      try {
        result = await importer(session.payload!);
      } catch (e) {
        result = const BleTransferResult(ok: false, message: 'Import failed on the receiver.');
      }
      await send(session.buildResult(result));

      var newlyTrusted = false;
      final trust = session.trustToSave;
      if (result.ok && trust != null) {
        await BleTrustStore.save(trust);
        newlyTrusted = !session.isTrusted;
        await reloadTrusted();
      }
      final sender = session.payload!.sender;
      final label = sender == null
          ? ''
          : [if (sender.name.isNotEmpty) sender.name, if (sender.username.isNotEmpty) sender.username].join(' - ');
      return BleReceiveOutcome(
        result: result,
        viaTrust: session.isTrusted,
        newlyTrusted: newlyTrusted,
        senderLabel: label.isEmpty ? null : label,
      );
    } on BleReceiveException {
      rethrow;
    } on BleProtocolException catch (e) {
      throw _failureFor(e.error, scout.tag);
    } catch (e) {
      debugPrint('BLE receive from phone ${scout.tag} failed: $e');
      throw const BleReceiveException(BleReceiveFailure.connect, 'The Bluetooth connection dropped. Try again.');
    } finally {
      if (deviceId != null) {
        try {
          await UniversalBle.disconnect(deviceId);
        } catch (_) {}
      }
      _busy = false;
      if (wasScanning && !_disposed) {
        try {
          await startScan();
        } catch (_) {}
      }
    }
  }

  static BleReceiveException _failureFor(BleTransferError error, String tag) {
    switch (error) {
      case BleTransferError.wrongCode:
        return BleReceiveException(BleReceiveFailure.wrongCode,
            'Wrong code. Phone $tag now shows a new code; enter that one.');
      case BleTransferError.busy:
        return BleReceiveException(BleReceiveFailure.busy, 'Phone $tag is sending to another receiver. Try again shortly.');
      case BleTransferError.locked:
        return BleReceiveException(BleReceiveFailure.locked,
            'Phone $tag stopped sending after too many wrong codes. The scout needs to restart it.');
      case BleTransferError.tooLarge:
        return const BleReceiveException(BleReceiveFailure.tooLarge, 'That entry is too large for Bluetooth.');
      case BleTransferError.unsupportedVersion:
        return const BleReceiveException(
            BleReceiveFailure.protocol, 'The two apps are on different versions. Update both and try again.');
      case BleTransferError.notTrusted:
      case BleTransferError.protocol:
      case BleTransferError.rejected:
        return BleReceiveException(BleReceiveFailure.protocol, 'Transfer from phone $tag failed. Try again.');
    }
  }
}
