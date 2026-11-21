/// Scout side of Bluetooth transfer: the phone advertises, shows a one-time code, and hands its entry to the
/// receiver that proves it knows the code, or to a receiver it already trusts.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_transfer_protocol.dart';
import 'ble_trust_store.dart';

enum BleSendState {
  /// Not started.
  idle,
  starting,

  /// Advertising and showing a code.
  waiting,

  /// A receiver sent a handshake; the transfer is under way.
  transferring,

  /// The receiver confirmed it imported the entry.
  delivered,

  /// Too many wrong codes. Advertising stopped until the scout restarts.
  locked,

  /// Bluetooth is off, unsupported, or permission was denied.
  unavailable,
  error,
}

class BleSendServer extends ChangeNotifier {
  BleSendServer({required this.payload, this.username});

  final BleTransferPayload payload;

  /// Signed-in username, shown to receivers this phone is paired with.
  final String? username;

  /// Seconds a receiver gets from its first message to the end of the transfer.
  static const Duration sessionTimeout = Duration(seconds: 30);

  /// The server that currently owns the GATT service and advertising. Only one can, app-wide.
  static BleSendServer? _active;

  /// Radio setup and teardown run one at a time, so a closing sheet cannot tear down the service a newly
  /// opened sheet just registered.
  static Future<void> _radioQueue = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() op) {
    final next = _radioQueue.then((_) => op());
    _radioQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  BleSendState state = BleSendState.idle;
  String tag = '';
  String code = '';
  int failedAttempts = 0;
  String? receiverName;
  String? message;

  /// Receivers allowed to pull entries from this phone without a code.
  List<BleTrustedPeer> trustedReceivers = const [];

  /// Set when the last delivery went to a trusted receiver (no code needed).
  bool deliveredViaTrust = false;

  /// Set when the last delivery also paired the receiver for next time.
  bool newlyTrusted = false;

  BleIdentity? _identity;

  String? _activeDevice;
  ScoutSession? _session;
  Timer? _sessionTimer;
  final Map<String, FrameReader> _readers = {};
  final Map<String, FrameWriter> _writers = {};
  final Map<String, List<Uint8List>> _outbox = {};
  final Map<String, Uint8List> _currentFrame = {};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Peripheral mode exists on Android, iOS, macOS and Windows.
  static bool get platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

  Future<void> start() async {
    if (_disposed ||
        state == BleSendState.starting ||
        state == BleSendState.waiting ||
        state == BleSendState.transferring) {
      return;
    }
    failedAttempts = 0;
    receiverName = null;
    message = null;
    deliveredViaTrust = false;
    newlyTrusted = false;
    _setState(BleSendState.starting);

    if (!platformSupported) {
      return _unavailable('Bluetooth sending is not supported on this device.');
    }
    if (payload.compressed.length > BleTransferProtocol.maxPayloadBytes) {
      message = 'This entry is too large to send over Bluetooth.';
      return _setState(BleSendState.error);
    }
    await _serial(_startLocked);
  }

  Future<void> _startLocked() async {
    if (_disposed) return;
    final previous = _active;
    if (previous != null && previous != this) {
      previous._endSession();
      await previous._teardownRadioLocked();
    }
    _active = this;
    try {
      if (!await _ensurePermissions()) {
        return _unavailable('Allow Bluetooth access for ObsidianScout to send entries.');
      }
      final caps = await UniversalBlePeripheral.getCapabilities();
      if (!caps.supportsPeripheralMode) {
        return _unavailable('This device cannot advertise over Bluetooth.');
      }
      final readiness = await UniversalBlePeripheral.getAvailabilityState();
      switch (readiness) {
        case PeripheralReadinessState.ready:
        case PeripheralReadinessState.unknown:
          break;
        case PeripheralReadinessState.bluetoothOff:
          return _unavailable('Turn on Bluetooth to send entries.');
        case PeripheralReadinessState.unauthorized:
          return _unavailable('Allow Bluetooth access for ObsidianScout to send entries.');
        case PeripheralReadinessState.unsupported:
          return _unavailable('This device cannot advertise over Bluetooth.');
      }

      if (isAndroid) {
        // Stop Android from silently reconnecting to past receivers in the background.
        await UniversalBlePeripheral.setAutoConnect(false);
      }
      _identity = (await BleTrustStore.identity()).withUsername(username);
      await _reloadTrusted();
      _listen();
      UniversalBlePeripheral.setReadRequestHandlers(_onRead);
      UniversalBlePeripheral.setWriteRequestHandlers(_onWrite);
      await _advertiseFresh();
    } catch (e) {
      debugPrint('BLE send start failed: $e');
      message = 'Could not start Bluetooth: ${_short(e)}';
      await _teardownRadioLocked();
      if (!_disposed) _setState(BleSendState.error);
    }
  }

  /// Starts again after a lockout or error with a fresh tag and code.
  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> stop() async {
    _sessionTimer?.cancel();
    _endSession();
    final subs = List.of(_subscriptions);
    _subscriptions.clear();
    for (final s in subs) {
      await s.cancel();
    }
    await _serial(() async {
      if (_active == this) {
        await _teardownRadioLocked();
        _active = null;
      }
    });
    if (!_disposed && state != BleSendState.delivered) _setState(BleSendState.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }

  Future<void> _reloadTrusted() async {
    trustedReceivers = await BleTrustStore.peers(BleTrustRole.receiver);
  }

  /// Stops trusting a receiver; it will need the code again.
  Future<void> forgetReceiver(String id) async {
    await BleTrustStore.remove(id, BleTrustRole.receiver);
    await _reloadTrusted();
    if (!_disposed) notifyListeners();
  }

  Future<bool> _ensurePermissions() async {
    if (!isAndroid) return true;
    // Android 12+ splits Bluetooth into advertise / connect / scan. Older versions grant these at install time.
    final results = await [Permission.bluetoothAdvertise, Permission.bluetoothConnect].request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  void _listen() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions
      ..clear()
      ..add(UniversalBlePeripheral.connectionStateStream.listen((event) {
        if (!event.connected) _onDisconnected(event.deviceId);
      }))
      ..add(UniversalBlePeripheral.advertisingStateStream.listen((event) {
        if (event.state == PeripheralAdvertisingState.error && state == BleSendState.waiting) {
          message = 'Bluetooth stopped advertising${event.error != null ? ': ${event.error}' : ''}.';
          _setState(BleSendState.error);
        }
      }));
  }

  Future<void> _advertiseFresh() async {
    tag = BleTransferProtocol.newTag();
    code = BleTransferProtocol.newCode();
    final uuid = BleTransferProtocol.serviceUuid(tag, BleTransferProtocol.beaconHint(_identity!.beaconKey, tag));
    await UniversalBlePeripheral.stopAdvertising().catchError((_) {});
    await UniversalBlePeripheral.clearServices();
    await UniversalBlePeripheral.addService(BlePeripheralService(
      uuid: uuid,
      primary: true,
      characteristics: [
        BlePeripheralCharacteristic(
          uuid: BleTransferProtocol.rxUuid,
          properties: [CharacteristicProperty.write],
          permissions: [PeripheralAttributePermission.writeable],
        ),
        BlePeripheralCharacteristic(
          uuid: BleTransferProtocol.txUuid,
          properties: [CharacteristicProperty.read],
          permissions: [PeripheralAttributePermission.readable],
        ),
      ],
    ));
    // No local name: on Android it would rename the phone's Bluetooth, and the tag in the UUID is enough.
    await UniversalBlePeripheral.startAdvertising(services: [uuid]);
    _setState(BleSendState.waiting);
  }

  /// Tears the service down if this server still owns it.
  Future<void> _teardownRadio() => _serial(() async {
        if (_active == this) await _teardownRadioLocked();
      });

  /// Caller holds the radio queue.
  Future<void> _teardownRadioLocked() async {
    UniversalBlePeripheral.setReadRequestHandlers(null);
    UniversalBlePeripheral.setWriteRequestHandlers(null);
    try {
      await UniversalBlePeripheral.stopAdvertising();
    } catch (_) {}
    try {
      await UniversalBlePeripheral.clearServices();
    } catch (_) {}
  }

  PeripheralWriteRequestResult? _onWrite(String deviceId, String characteristicId, int offset, Uint8List? value) {
    if (_active != this || _disposed || characteristicId.toLowerCase() != BleTransferProtocol.rxUuid || value == null) {
      return PeripheralWriteRequestResult();
    }
    if (state != BleSendState.waiting && state != BleSendState.transferring) {
      _queue(deviceId, errorMessage(state == BleSendState.locked ? BleTransferError.locked : BleTransferError.busy));
      return PeripheralWriteRequestResult();
    }
    if (!_readers.containsKey(deviceId)) {
      // A new conversation from this receiver: both directions restart at sequence 0.
      _writers.remove(deviceId);
      _outbox.remove(deviceId);
      _currentFrame.remove(deviceId);
    }
    Uint8List? message;
    try {
      message = _readers.putIfAbsent(deviceId, FrameReader.new).add(value);
    } on BleProtocolException catch (e) {
      _queue(deviceId, errorMessage(e.error));
      if (deviceId == _activeDevice) _finishFailed(e.error);
      return PeripheralWriteRequestResult();
    }
    if (message != null) {
      final complete = message;
      // Let the write response go out before the handshake math runs.
      Future<void>.microtask(() => _onMessage(deviceId, complete));
    }
    return PeripheralWriteRequestResult();
  }

  PeripheralReadRequestResult? _onRead(String deviceId, String characteristicId, int offset, Uint8List? value) {
    if (characteristicId.toLowerCase() != BleTransferProtocol.txUuid) {
      return PeripheralReadRequestResult(value: Uint8List(0));
    }
    if (offset > 0) {
      // Frames fit in one read, so a long read only happens if a stack ignores the MTU we sized for.
      // Android expects the slice from us; Apple slices for us.
      final current = _currentFrame[deviceId] ?? Uint8List(0);
      if (isAndroid) {
        final start = offset > current.length ? current.length : offset;
        return PeripheralReadRequestResult(value: Uint8List.sublistView(current, start), offset: offset);
      }
      return PeripheralReadRequestResult(value: current);
    }
    final queue = _outbox[deviceId];
    if (queue == null || queue.isEmpty) {
      _currentFrame.remove(deviceId);
      return PeripheralReadRequestResult(value: Uint8List(0));
    }
    final frame = queue.removeAt(0);
    _currentFrame[deviceId] = frame;
    return PeripheralReadRequestResult(value: frame);
  }

  void _onMessage(String deviceId, Uint8List message) {
    if (_disposed) return;
    if (_activeDevice != null && _activeDevice != deviceId) {
      _queue(deviceId, errorMessage(BleTransferError.busy));
      return;
    }
    if (_activeDevice == null) {
      final isCodeHello = message.isNotEmpty && message[0] == BleMessageType.hello.code;
      final isTrustedHello = message.isNotEmpty && message[0] == BleMessageType.trustedHello.code;
      if (!isCodeHello && !isTrustedHello) {
        _queue(deviceId, errorMessage(BleTransferError.protocol));
        return;
      }
      _activeDevice = deviceId;
      _session = ScoutSession(
        tag: tag,
        code: code,
        payload: payload,
        identity: _identity!,
        trustedReceivers: {for (final p in trustedReceivers) p.id: p},
      );
      _sessionTimer?.cancel();
      _sessionTimer = Timer(sessionTimeout, () => _finishFailed(BleTransferError.protocol));
      if (isCodeHello) {
        // The code is single use: whatever happens next, show a new one.
        code = BleTransferProtocol.newCode();
      }
      _setState(BleSendState.transferring);
    }

    final session = _session!;
    final List<Uint8List> replies;
    try {
      replies = session.handle(message);
    } catch (e) {
      debugPrint('BLE send session error: $e');
      _queue(deviceId, errorMessage(BleTransferError.protocol));
      _finishFailed(BleTransferError.protocol);
      return;
    }
    for (final reply in replies) {
      _queue(deviceId, reply, mtu: session.peerMtu);
    }

    if (session.stage == ScoutSessionStage.failed) {
      _finishFailed(session.failure ?? BleTransferError.protocol);
    } else if (session.stage == ScoutSessionStage.finished) {
      final trust = session.trustToSave;
      deliveredViaTrust = session.trustedPeer != null;
      newlyTrusted = trust != null && session.trustedPeer == null;
      if (trust != null) {
        BleTrustStore.save(trust).then((_) => _reloadTrusted()).then((_) {
          if (!_disposed) notifyListeners();
        });
      }
      _finishDelivered(session.result!);
    }
  }

  void _queue(String deviceId, Uint8List message, {int mtu = 23}) {
    // A read returns at most MTU-1 bytes; MTU-3 matches the notify limit and leaves margin.
    final frames = _writers.putIfAbsent(deviceId, FrameWriter.new).split(message, mtu - 3);
    _outbox.putIfAbsent(deviceId, () => []).addAll(frames);
  }

  void _onDisconnected(String deviceId) {
    _readers.remove(deviceId);
    _writers.remove(deviceId);
    _outbox.remove(deviceId);
    _currentFrame.remove(deviceId);
    if (deviceId == _activeDevice && state == BleSendState.transferring) {
      _finishFailed(BleTransferError.protocol);
    }
  }

  void _finishFailed(BleTransferError error) {
    if (_session == null) return;
    final authenticated = _session!.authenticated;
    final codeTried = _session!.codeConsumed;
    _sessionTimer?.cancel();
    if (error == BleTransferError.notTrusted) {
      // Trust didn't match. The receiver falls back to the code on this same connection, so keep the frame
      // sequence going and don't count it: no code was guessed.
      _activeDevice = null;
      _session = null;
      if (!_disposed) _setState(BleSendState.waiting);
      return;
    }
    _endSession(keepOutbox: true);
    if (_disposed) return;

    if (codeTried && !authenticated) {
      // The code was tried (or the attempt was abandoned, which also spends a guess).
      failedAttempts++;
      if (failedAttempts >= BleTransferProtocol.maxFailedAttempts) {
        message = 'Too many wrong codes. Bluetooth sending stopped.';
        _teardownRadio();
        _setState(BleSendState.locked);
        return;
      }
      message = error == BleTransferError.wrongCode
          ? 'Wrong code entered on the receiver. Use the new code.'
          : 'The receiver disconnected. Use the new code to try again.';
    } else if (!codeTried && !authenticated) {
      message = null;
    } else {
      message = 'The transfer was interrupted. Try again.';
    }
    _setState(BleSendState.waiting);
  }

  void _finishDelivered(BleTransferResult result) {
    _sessionTimer?.cancel();
    final info = result.receiver;
    final label = info == null
        ? result.receiverName
        : [if (info.name.isNotEmpty) info.name, if (info.username.isNotEmpty) info.username].join(' - ');
    receiverName = label.isEmpty ? null : label;
    _endSession();
    if (_disposed) return;
    if (result.ok) {
      message = result.message.isEmpty ? null : result.message;
      _setState(BleSendState.delivered);
      // Give the receiver's last write a moment to be acknowledged before the service goes away.
      Future<void>.delayed(const Duration(milliseconds: 600), () async {
        if (state == BleSendState.delivered) await _teardownRadio();
      });
    } else {
      message = result.message.isEmpty ? 'The receiver could not import this entry.' : result.message;
      _setState(BleSendState.waiting);
    }
  }

  void _endSession({bool keepOutbox = false}) {
    final device = _activeDevice;
    _activeDevice = null;
    _session = null;
    if (device != null) {
      _readers.remove(device);
      if (!keepOutbox) {
        _writers.remove(device);
        _outbox.remove(device);
        _currentFrame.remove(device);
      }
    }
  }

  void _unavailable(String why) {
    message = why;
    _setState(BleSendState.unavailable);
  }

  void _setState(BleSendState next) {
    if (_disposed) return;
    state = next;
    notifyListeners();
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}...' : s;
  }
}
