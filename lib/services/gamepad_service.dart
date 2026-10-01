import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gamepad_models.dart';
import 'file_download_helper.dart';

typedef GamepadInputListenCallback = void Function(String inputKey, String displayName, bool isAnalog);

class GamepadDeviceInfo {
  final String id;
  final String name;
  final String inferredType; // 'xbox', 'playstation', 'generic'

  const GamepadDeviceInfo({
    required this.id,
    required this.name,
    required this.inferredType,
  });
}

class GamepadService with ChangeNotifier, WidgetsBindingObserver {
  static final GamepadService _instance = GamepadService._internal();
  static GamepadService get instance => _instance;

  static const String _activeProfilePrefKey = 'obsidian_gamepad_active_profile_v1';
  static const String _allProfilesPrefKey = 'obsidian_gamepad_all_profiles_v1';

  // Gamepad stream subscription
  StreamSubscription<GamepadEvent>? _gamepadSubscription;
  Timer? _devicePollTimer;

  // Controllers list
  List<GamepadDeviceInfo> _connectedDevices = [];
  List<GamepadDeviceInfo> get connectedDevices => List.unmodifiable(_connectedDevices);

  // Profiles
  List<GamepadProfile> _profiles = [];
  List<GamepadProfile> get profiles => List.unmodifiable(_profiles);

  GamepadProfile? _activeProfile;
  GamepadProfile? get activeProfile => _activeProfile;

  // Live input state (for testing HUD and trigger scaling)
  final Map<String, double> _liveInputValues = {};
  Map<String, double> get liveInputValues => Map.unmodifiable(_liveInputValues);

  final Map<String, bool> _liveInputPressed = {};
  Map<String, bool> get liveInputPressed => Map.unmodifiable(_liveInputPressed);

  // Action Dispatcher stream
  final StreamController<GamepadActionEvent> _actionController = StreamController<GamepadActionEvent>.broadcast();
  Stream<GamepadActionEvent> get actionStream => _actionController.stream;

  // Hold-to-repeat timers: bindingId -> Timer
  final Map<String, Timer> _repeatTimers = {};
  final Map<String, double> _activeBindingValues = {};

  // Interactive input capture mode (for "Press button on controller to bind")
  bool _isListeningForBinding = false;
  bool get isListeningForBinding => _isListeningForBinding;
  GamepadInputListenCallback? _onBindingCaptured;

  GamepadService._internal();

  /// Initialize the Gamepad Service, load profiles, start input listeners
  Future<void> init() async {
    await _loadProfiles();
    _initGamepadListener();
    _initHardwareKeyboardListener();
    WidgetsBinding.instance.addObserver(this);
    await refreshConnectedDevices();
    _startDevicePolling();
  }

  void _startDevicePolling() {
    _devicePollTimer?.cancel();
    _devicePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      refreshConnectedDevices();
    });
  }

  /// Cancels all repeating timers and resets all live inputs to null / 0 / false to avoid runaway inputs.
  void resetAllInputs({String? reason}) {
    // 1. Cancel and clear all hold-to-repeat and scaled trigger timers
    for (final timer in _repeatTimers.values) {
      timer.cancel();
    }
    _repeatTimers.clear();
    _activeBindingValues.clear();

    // 2. Clear / zero live input states to avoid runaway inputs
    _liveInputValues.clear();
    _liveInputPressed.clear();

    // 3. Cancel interactive binding listener if waiting on input
    if (_isListeningForBinding) {
      _isListeningForBinding = false;
      _onBindingCaptured = null;
    }

    if (reason != null) {
      debugPrint('[GamepadService] Reset all inputs ($reason)');
    }

    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      resetAllInputs(reason: 'App lifecycle state: $state');
    }
  }

  /// Refreshes the list of currently connected gamepads and detects disconnections
  Future<void> refreshConnectedDevices() async {
    try {
      final list = await Gamepads.list();
      final previousIds = _connectedDevices.map((c) => c.id).toSet();
      final newDevices = list.map((c) {
        final nameLower = c.name.toLowerCase();
        String type = 'generic';
        if (nameLower.contains('xbox') || nameLower.contains('microsoft') || nameLower.contains('x-input')) {
          type = 'xbox';
        } else if (nameLower.contains('ps4') ||
            nameLower.contains('ps5') ||
            nameLower.contains('dualshock') ||
            nameLower.contains('dualsense') ||
            nameLower.contains('playstation') ||
            nameLower.contains('sony')) {
          type = 'playstation';
        }
        return GamepadDeviceInfo(
          id: c.id,
          name: c.name.isNotEmpty ? c.name : 'Gamepad ${c.id}',
          inferredType: type,
        );
      }).toList();

      final newIds = newDevices.map((c) => c.id).toSet();
      final hasDisconnected = previousIds.difference(newIds).isNotEmpty || (list.isEmpty && previousIds.isNotEmpty);
      final hasConnected = newIds.difference(previousIds).isNotEmpty;

      _connectedDevices = newDevices;

      if (hasDisconnected) {
        // Disconnection detected: immediately clear all live inputs and timers to prevent runaway actions
        resetAllInputs(reason: 'Gamepad disconnected');
      } else if (hasConnected) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[GamepadService] Error listing gamepads: $e');
    }
  }

  void _initGamepadListener() {
    _gamepadSubscription?.cancel();
    try {
      _gamepadSubscription = Gamepads.events.listen(
        (event) {
          _handleRawGamepadEvent(event);
        },
        onError: (err) {
          debugPrint('[GamepadService] Gamepad stream error: $err');
          resetAllInputs(reason: 'Gamepad stream error');
        },
        onDone: () {
          debugPrint('[GamepadService] Gamepad stream closed');
          resetAllInputs(reason: 'Gamepad stream closed');
        },
      );
    } catch (e) {
      debugPrint('[GamepadService] Could not subscribe to Gamepads.events: $e');
    }
  }

  void _initHardwareKeyboardListener() {
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (_activeProfile != null && !_activeProfile!.enabled && !_isListeningForBinding) {
      return false;
    }

    // When typing into a text input, don't trigger action bindings unless listening for binding recording
    if (!_isListeningForBinding) {
      final primaryFocus = FocusManager.instance.primaryFocus;
      if (primaryFocus != null && primaryFocus.hasFocus) {
        final widget = primaryFocus.context?.widget;
        if (widget is EditableText) {
          return false;
        }
      }
    }

    final key = event.logicalKey;
    final normalizedKey = _normalizeLogicalKey(key);
    if (normalizedKey == null) return false;

    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final isUp = event is KeyUpEvent;

    if (isDown) {
      _processInput(
        inputKey: normalizedKey,
        value: 1.0,
        isPressed: true,
        isAnalog: false,
      );
    } else if (isUp) {
      _processInput(
        inputKey: normalizedKey,
        value: 0.0,
        isPressed: false,
        isAnalog: false,
      );
    }

    return false; // Don't block OS event
  }

  void _handleRawGamepadEvent(GamepadEvent event) {
    final normalizedKey = _normalizeRawGamepadKey(event.key);
    final value = event.value;

    // Decompose analog stick axes into directional virtual button events
    if (normalizedKey == 'stick_l_x') {
      _processStickAxis(stickPrefix: 'stick_l', isXAxis: true, value: value, gamepadId: event.gamepadId);
    } else if (normalizedKey == 'stick_l_y') {
      _processStickAxis(stickPrefix: 'stick_l', isXAxis: false, value: value, gamepadId: event.gamepadId);
    } else if (normalizedKey == 'stick_r_x') {
      _processStickAxis(stickPrefix: 'stick_r', isXAxis: true, value: value, gamepadId: event.gamepadId);
    } else if (normalizedKey == 'stick_r_y') {
      _processStickAxis(stickPrefix: 'stick_r', isXAxis: false, value: value, gamepadId: event.gamepadId);
    }

    final isAnalog = _isKeyAnalog(normalizedKey);
    final threshold = isAnalog ? 0.15 : 0.4;
    final isPressed = value.abs() > threshold;

    _processInput(
      inputKey: normalizedKey,
      value: value,
      isPressed: isPressed,
      isAnalog: isAnalog,
      gamepadId: event.gamepadId,
    );
  }

  void _processStickAxis({
    required String stickPrefix,
    required bool isXAxis,
    required double value,
    String? gamepadId,
  }) {
    // Note: On standard controller Y-axis, negative is often UP (direct input) or positive is UP (XInput).
    // We treat positive as Right / Up and negative as Left / Down.
    final posKey = isXAxis ? '${stickPrefix}_right' : '${stickPrefix}_up';
    final negKey = isXAxis ? '${stickPrefix}_left' : '${stickPrefix}_down';
    const deadzone = 0.4;

    if (value > deadzone) {
      _processInput(inputKey: posKey, value: value, isPressed: true, isAnalog: false, gamepadId: gamepadId);
      _processInput(inputKey: negKey, value: 0.0, isPressed: false, isAnalog: false, gamepadId: gamepadId);
    } else if (value < -deadzone) {
      _processInput(inputKey: negKey, value: value.abs(), isPressed: true, isAnalog: false, gamepadId: gamepadId);
      _processInput(inputKey: posKey, value: 0.0, isPressed: false, isAnalog: false, gamepadId: gamepadId);
    } else if (value.abs() < 0.2) {
      if (_liveInputPressed[posKey] == true) {
        _processInput(inputKey: posKey, value: 0.0, isPressed: false, isAnalog: false, gamepadId: gamepadId);
      }
      if (_liveInputPressed[negKey] == true) {
        _processInput(inputKey: negKey, value: 0.0, isPressed: false, isAnalog: false, gamepadId: gamepadId);
      }
    }
  }

  /// Process unified input event (from either plugin or hardware keyboard)
  void _processInput({
    required String inputKey,
    required double value,
    required bool isPressed,
    required bool isAnalog,
    String? gamepadId,
  }) {
    final wasPressed = _liveInputPressed[inputKey] ?? false;
    _liveInputValues[inputKey] = value;
    _liveInputPressed[inputKey] = isPressed;

    // 1. If currently recording a binding in Settings
    if (_isListeningForBinding) {
      final captureThreshold = isAnalog ? 0.35 : 0.5;
      if (value.abs() >= captureThreshold) {
        final displayName = getButtonDisplayName(
          inputKey,
          controllerType: _activeProfile?.controllerType ?? 'xbox',
        );
        _onBindingCaptured?.call(inputKey, displayName, isAnalog);
        _isListeningForBinding = false;
        _onBindingCaptured = null;
        notifyListeners();
        return;
      }
    }

    notifyListeners();

    // 2. Dispatch to bindings
    if (_activeProfile == null || !_activeProfile!.enabled) return;

    // If specific controller is selected, filter by it
    if (_activeProfile!.selectedGamepadId != null &&
        gamepadId != null &&
        _activeProfile!.selectedGamepadId != gamepadId) {
      return;
    }

    // Match bindings for this inputKey
    final matchingBindings = _activeProfile!.bindings.where((b) => b.inputKey == inputKey).toList();
    if (matchingBindings.isEmpty) return;

    for (final binding in matchingBindings) {
      _handleBindingInput(
        binding: binding,
        value: value,
        isPressed: isPressed,
        wasPressed: wasPressed,
      );
    }
  }

  void _handleBindingInput({
    required GamepadBinding binding,
    required double value,
    required bool isPressed,
    required bool wasPressed,
  }) {
    final bindingId = binding.id;
    _activeBindingValues[bindingId] = value;

    // Single press mode
    if (binding.triggerMode == GamepadTriggerMode.singlePress) {
      // Fire once on edge transition (false -> true)
      if (isPressed && !wasPressed) {
        _actionController.add(GamepadActionEvent(
          binding: binding,
          value: value,
          isRepeat: false,
        ));
      }
      return;
    }

    // Continuous hold mode (Fixed Hz)
    if (binding.triggerMode == GamepadTriggerMode.continuousHold) {
      if (isPressed && !wasPressed) {
        // Fire initial immediately
        _actionController.add(GamepadActionEvent(
          binding: binding,
          value: value,
          isRepeat: false,
        ));

        // Start repeat timer
        _repeatTimers[bindingId]?.cancel();
        final hz = binding.repeatFrequencyHz.clamp(1.0, 30.0);
        final intervalMs = (1000.0 / hz).round();

        _repeatTimers[bindingId] = Timer.periodic(
          Duration(milliseconds: intervalMs),
          (_) {
            if (!(_liveInputPressed[binding.inputKey] ?? false)) {
              _repeatTimers[bindingId]?.cancel();
              _repeatTimers.remove(bindingId);
              return;
            }
            _actionController.add(GamepadActionEvent(
              binding: binding,
              value: _activeBindingValues[bindingId] ?? 1.0,
              isRepeat: true,
            ));
          },
        );
      } else if (!isPressed && wasPressed) {
        _repeatTimers[bindingId]?.cancel();
        _repeatTimers.remove(bindingId);
      }
      return;
    }

    // Scaled Trigger mode (Analog Pressure-Sensitive Repeat)
    if (binding.triggerMode == GamepadTriggerMode.scaledTrigger) {
      final effectiveValue = value.abs();
      final threshold = binding.triggerThreshold.clamp(0.05, 0.5);

      if (effectiveValue >= threshold) {
        // If not running, fire initial and start variable loop
        if (!_repeatTimers.containsKey(bindingId)) {
          _actionController.add(GamepadActionEvent(
            binding: binding,
            value: effectiveValue,
            isRepeat: false,
          ));
          _scheduleScaledRepeat(binding);
        }
      } else {
        _repeatTimers[bindingId]?.cancel();
        _repeatTimers.remove(bindingId);
      }
    }
  }

  void _scheduleScaledRepeat(GamepadBinding binding) {
    final bindingId = binding.id;
    final currentVal = (_activeBindingValues[bindingId] ?? 0.0).abs();
    final threshold = binding.triggerThreshold.clamp(0.05, 0.5);

    if (currentVal < threshold) {
      _repeatTimers[bindingId]?.cancel();
      _repeatTimers.remove(bindingId);
      return;
    }

    // Calculate dynamic Hz based on pressure depth between threshold and 1.0
    final normalizedPressure = ((currentVal - threshold) / (1.0 - threshold)).clamp(0.0, 1.0);
    final minHz = binding.triggerMinHz.clamp(1.0, 20.0);
    final maxHz = binding.triggerMaxHz.clamp(minHz, 40.0);
    final currentHz = minHz + (maxHz - minHz) * normalizedPressure;
    final intervalMs = (1000.0 / currentHz).round().clamp(20, 1000);

    _repeatTimers[bindingId] = Timer(Duration(milliseconds: intervalMs), () {
      if ((_liveInputValues[binding.inputKey]?.abs() ?? 0.0) >= threshold) {
        _actionController.add(GamepadActionEvent(
          binding: binding,
          value: _activeBindingValues[bindingId] ?? currentVal,
          isRepeat: true,
        ));
        _scheduleScaledRepeat(binding);
      } else {
        _repeatTimers.remove(bindingId);
      }
    });
  }

  // ==========================================
  // BINDING RECORDING
  // ==========================================

  /// Start recording the next button/trigger pressed
  void startListeningForBinding(GamepadInputListenCallback onCaptured) {
    _isListeningForBinding = true;
    _onBindingCaptured = onCaptured;
    notifyListeners();
  }

  void cancelListeningForBinding() {
    _isListeningForBinding = false;
    _onBindingCaptured = null;
    notifyListeners();
  }

  // ==========================================
  // PROFILE MANAGEMENT & IMPORT/EXPORT
  // ==========================================

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final allJson = prefs.getString(_allProfilesPrefKey);

    if (allJson != null && allJson.isNotEmpty) {
      try {
        final decoded = json.decode(allJson) as List<dynamic>;
        _profiles = decoded
            .whereType<Map<String, dynamic>>()
            .map((p) => GamepadProfile.fromJson(p))
            .toList();
      } catch (e) {
        debugPrint('[GamepadService] Error parsing stored profiles: $e');
      }
    }

    if (_profiles.isEmpty) {
      _profiles = [
        GamepadProfile.defaultXbox(),
        GamepadProfile.defaultPlayStation(),
        GamepadProfile.defaultKeyboard(),
      ];
      await _saveProfiles();
    }

    final activeId = prefs.getString(_activeProfilePrefKey);
    if (activeId != null) {
      _activeProfile = _profiles.where((p) => p.id == activeId).firstOrNull;
    }
    _activeProfile ??= _profiles.first;
    notifyListeners();
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final listJson = json.encode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString(_allProfilesPrefKey, listJson);
    if (_activeProfile != null) {
      await prefs.setString(_activeProfilePrefKey, _activeProfile!.id);
    }
  }

  Future<void> setActiveProfile(GamepadProfile profile) async {
    _activeProfile = profile;
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;
    } else {
      _profiles.add(profile);
    }
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> saveProfile(GamepadProfile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;
    } else {
      _profiles.add(profile);
    }
    if (_activeProfile?.id == profile.id) {
      _activeProfile = profile;
    }
    await _saveProfiles();
    notifyListeners();
  }

  Future<void> deleteProfile(String profileId) async {
    _profiles.removeWhere((p) => p.id == profileId);
    if (_profiles.isEmpty) {
      _profiles.add(GamepadProfile.defaultXbox());
    }
    if (_activeProfile?.id == profileId) {
      _activeProfile = _profiles.first;
    }
    await _saveProfiles();
    notifyListeners();
  }

  /// Exports the profile as JSON string
  String exportProfileToJson(GamepadProfile profile) {
    return profile.exportJson(pretty: true);
  }

  /// Exports profile and saves as a downloadable/local file
  Future<FileDownloadResult> exportProfileToFile(GamepadProfile profile) async {
    final jsonStr = exportProfileToJson(profile);
    final sanitizedName = profile.name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_').toLowerCase();
    final fileName = 'gamepad_profile_${sanitizedName}_${DateTime.now().millisecondsSinceEpoch}.json';

    return downloadOrSaveFile(
      filename: fileName,
      content: jsonStr,
      mimeType: 'application/json',
    );
  }

  /// Copies profile JSON to clipboard
  Future<void> copyProfileToClipboard(GamepadProfile profile) async {
    final jsonStr = exportProfileToJson(profile);
    await Clipboard.setData(ClipboardData(text: jsonStr));
  }

  /// Imports a profile from a JSON string and saves it
  Future<GamepadProfile?> importProfileFromJson(String jsonString, {bool setActive = true}) async {
    final imported = GamepadProfile.importJson(jsonString);
    if (imported == null) return null;

    // Create unique ID if exists
    var newId = imported.id;
    if (_profiles.any((p) => p.id == newId)) {
      newId = '${imported.id}_imported_${DateTime.now().millisecondsSinceEpoch}';
    }

    final newProfile = imported.copyWith(
      id: newId,
      name: imported.name.contains('(Imported)') ? imported.name : '${imported.name} (Imported)',
      updatedAt: DateTime.now(),
    );

    _profiles.add(newProfile);
    if (setActive) {
      _activeProfile = newProfile;
    }
    await _saveProfiles();
    notifyListeners();
    return newProfile;
  }

  /// Imports a profile from system clipboard
  Future<GamepadProfile?> importProfileFromClipboard({bool setActive = true}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.trim().isEmpty) return null;
    return importProfileFromJson(data.text!.trim(), setActive: setActive);
  }

  // ==========================================
  // BUTTON GLYPHS & FORMATTING HELPERS
  // ==========================================

  static String getButtonDisplayName(String key, {String controllerType = 'xbox'}) {
    final isPs = controllerType == 'playstation';

    switch (key.toLowerCase()) {
      case 'button_a':
      case 'button_south':
      case 'buttona':
        return isPs ? '✕ Cross' : 'A';
      case 'button_b':
      case 'button_east':
      case 'buttonb':
        return isPs ? '○ Circle' : 'B';
      case 'button_x':
      case 'button_west':
      case 'buttonx':
        return isPs ? '□ Square' : 'X';
      case 'button_y':
      case 'button_north':
      case 'buttony':
        return isPs ? '△ Triangle' : 'Y';
      case 'shoulder_l':
      case 'l1':
      case 'leftshoulder':
        return isPs ? 'L1' : 'LB';
      case 'shoulder_r':
      case 'r1':
      case 'rightshoulder':
        return isPs ? 'R1' : 'RB';
      case 'trigger_l':
      case 'l2':
      case 'lefttrigger':
        return isPs ? 'L2 (Trigger)' : 'LT (Trigger)';
      case 'trigger_r':
      case 'r2':
      case 'righttrigger':
        return isPs ? 'R2 (Trigger)' : 'RT (Trigger)';
      case 'dpad_up':
      case 'dpadup':
        return 'D-Pad ↑';
      case 'dpad_down':
      case 'dpaddown':
        return 'D-Pad ↓';
      case 'dpad_left':
      case 'dpadleft':
        return 'D-Pad ←';
      case 'dpad_right':
      case 'dpadright':
        return 'D-Pad →';
      case 'thumb_l':
      case 'l3':
      case 'leftthumbstick':
        return isPs ? 'L3' : 'LS (Left Stick)';
      case 'thumb_r':
      case 'r3':
      case 'rightthumbstick':
        return isPs ? 'R3' : 'RS (Right Stick)';
      case 'stick_l_up':
        return 'L-Stick ↑';
      case 'stick_l_down':
        return 'L-Stick ↓';
      case 'stick_l_left':
        return 'L-Stick ←';
      case 'stick_l_right':
        return 'L-Stick →';
      case 'stick_r_up':
        return 'R-Stick ↑';
      case 'stick_r_down':
        return 'R-Stick ↓';
      case 'stick_r_left':
        return 'R-Stick ←';
      case 'stick_r_right':
        return 'R-Stick →';
      case 'button_start':
      case 'menu':
      case 'buttonstart':
        return isPs ? 'Options' : 'Menu (≡)';
      case 'button_back':
      case 'view':
      case 'select':
      case 'buttonback':
        return isPs ? 'Share' : 'View (⧉)';
      case 'stick_l_x':
        return 'L-Stick X Axis';
      case 'stick_l_y':
        return 'L-Stick Y Axis';
      case 'stick_r_x':
        return 'R-Stick X Axis';
      case 'stick_r_y':
        return 'R-Stick Y Axis';
      case 'key_space':
        return 'Spacebar';
      case 'key_enter':
        return 'Enter (⏎)';
      case 'key_tab':
        return 'Tab';
      case 'key_escape':
        return 'Esc';
      case 'key_backspace':
        return 'Backspace';
      case 'key_arrow_up':
        return 'Arrow ↑';
      case 'key_arrow_down':
        return 'Arrow ↓';
      case 'key_arrow_left':
        return 'Arrow ←';
      case 'key_arrow_right':
        return 'Arrow →';
      case 'key_shift':
        return 'Shift';
      case 'key_control':
        return 'Ctrl';
      case 'key_alt':
        return 'Alt';
      default:
        if (key.toLowerCase().startsWith('key_')) {
          return 'Key ${key.substring(4).toUpperCase()}';
        }
        return key.replaceAll('_', ' ').toUpperCase();
    }
  }

  static String getShortBadgeLabel(String key, {String controllerType = 'xbox'}) {
    final isPs = controllerType == 'playstation';

    switch (key.toLowerCase()) {
      case 'button_a':
      case 'button_south':
      case 'buttona':
        return isPs ? '✕' : 'A';
      case 'button_b':
      case 'button_east':
      case 'buttonb':
        return isPs ? '○' : 'B';
      case 'button_x':
      case 'button_west':
      case 'buttonx':
        return isPs ? '□' : 'X';
      case 'button_y':
      case 'button_north':
      case 'buttony':
        return isPs ? '△' : 'Y';
      case 'shoulder_l':
      case 'l1':
      case 'leftshoulder':
        return isPs ? 'L1' : 'LB';
      case 'shoulder_r':
      case 'r1':
      case 'rightshoulder':
        return isPs ? 'R1' : 'RB';
      case 'trigger_l':
      case 'l2':
      case 'lefttrigger':
        return isPs ? 'L2' : 'LT';
      case 'trigger_r':
      case 'r2':
      case 'righttrigger':
        return isPs ? 'R2' : 'RT';
      case 'dpad_up':
      case 'dpadup':
        return '▲';
      case 'dpad_down':
      case 'dpaddown':
        return '▼';
      case 'dpad_left':
      case 'dpadleft':
        return '◄';
      case 'dpad_right':
      case 'dpadright':
        return '►';
      case 'stick_l_up':
        return 'L↑';
      case 'stick_l_down':
        return 'L↓';
      case 'stick_l_left':
        return 'L←';
      case 'stick_l_right':
        return 'L→';
      case 'stick_r_up':
        return 'R↑';
      case 'stick_r_down':
        return 'R↓';
      case 'stick_r_left':
        return 'R←';
      case 'stick_r_right':
        return 'R→';
      case 'thumb_l':
      case 'l3':
      case 'leftthumbstick':
        return 'L3';
      case 'thumb_r':
      case 'r3':
      case 'rightthumbstick':
        return 'R3';
      case 'button_start':
      case 'buttonstart':
        return '≡';
      case 'button_back':
      case 'buttonback':
        return '⧉';
      case 'key_space':
        return '␣';
      case 'key_enter':
        return '⏎';
      case 'key_tab':
        return '⇥';
      case 'key_escape':
        return 'Esc';
      case 'key_backspace':
        return '⌫';
      case 'key_arrow_up':
        return '↑';
      case 'key_arrow_down':
        return '↓';
      case 'key_arrow_left':
        return '←';
      case 'key_arrow_right':
        return '→';
      default:
        if (key.toLowerCase().startsWith('key_')) {
          return key.substring(4).toUpperCase();
        }
        return key.toUpperCase();
    }
  }

  bool _isKeyAnalog(String key) {
    final lower = key.toLowerCase();
    return lower.startsWith('trigger_') ||
        lower.startsWith('stick_') ||
        lower == 'l2' ||
        lower == 'r2' ||
        lower == 'lefttrigger' ||
        lower == 'righttrigger';
  }

  String? _normalizeLogicalKey(LogicalKeyboardKey key) {
    // 1. Explicit Gamepad logical keys
    if (key == LogicalKeyboardKey.gameButtonA) return 'button_a';
    if (key == LogicalKeyboardKey.gameButtonB) return 'button_b';
    if (key == LogicalKeyboardKey.gameButtonX) return 'button_x';
    if (key == LogicalKeyboardKey.gameButtonY) return 'button_y';
    if (key == LogicalKeyboardKey.gameButtonLeft1) return 'shoulder_l';
    if (key == LogicalKeyboardKey.gameButtonRight1) return 'shoulder_r';
    if (key == LogicalKeyboardKey.gameButtonLeft2) return 'trigger_l';
    if (key == LogicalKeyboardKey.gameButtonRight2) return 'trigger_r';
    if (key == LogicalKeyboardKey.gameButtonSelect) return 'button_back';
    if (key == LogicalKeyboardKey.gameButtonStart) return 'button_start';
    if (key == LogicalKeyboardKey.gameButtonThumbLeft) return 'thumb_l';
    if (key == LogicalKeyboardKey.gameButtonThumbRight) return 'thumb_r';
    if (key == LogicalKeyboardKey.gameButtonMode) return 'button_start';

    // 2. Keyboard Navigation & Controls
    if (key == LogicalKeyboardKey.space) return 'key_space';
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) return 'key_enter';
    if (key == LogicalKeyboardKey.tab) return 'key_tab';
    if (key == LogicalKeyboardKey.escape) return 'key_escape';
    if (key == LogicalKeyboardKey.backspace) return 'key_backspace';
    if (key == LogicalKeyboardKey.arrowUp) return 'key_arrow_up';
    if (key == LogicalKeyboardKey.arrowDown) return 'key_arrow_down';
    if (key == LogicalKeyboardKey.arrowLeft) return 'key_arrow_left';
    if (key == LogicalKeyboardKey.arrowRight) return 'key_arrow_right';

    // 3. Letters A-Z & Digits 0-9
    final keyLabel = key.keyLabel.toLowerCase().trim();
    if (keyLabel.length == 1 && RegExp(r'^[a-z0-9]$').hasMatch(keyLabel)) {
      return 'key_$keyLabel';
    }

    // 4. Function keys F1-F12
    if (key.keyId >= LogicalKeyboardKey.f1.keyId && key.keyId <= LogicalKeyboardKey.f12.keyId) {
      final fNum = key.keyId - LogicalKeyboardKey.f1.keyId + 1;
      return 'key_f$fNum';
    }

    // 5. Numpad numbers
    if (key.keyId >= LogicalKeyboardKey.numpad0.keyId && key.keyId <= LogicalKeyboardKey.numpad9.keyId) {
      final num = key.keyId - LogicalKeyboardKey.numpad0.keyId;
      return 'key_num$num';
    }

    // 6. Common punctuation / symbols
    if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) return 'key_minus';
    if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) return 'key_plus';
    if (key == LogicalKeyboardKey.bracketLeft) return 'key_bracket_left';
    if (key == LogicalKeyboardKey.bracketRight) return 'key_bracket_right';
    if (key == LogicalKeyboardKey.semicolon) return 'key_semicolon';
    if (key == LogicalKeyboardKey.quote) return 'key_quote';
    if (key == LogicalKeyboardKey.comma) return 'key_comma';
    if (key == LogicalKeyboardKey.period) return 'key_period';
    if (key == LogicalKeyboardKey.slash) return 'key_slash';
    if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) return 'key_shift';
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) return 'key_control';
    if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) return 'key_alt';

    // 7. Label based fallback matching
    final label = key.keyLabel.toLowerCase();
    if (label.contains('button a')) return 'button_a';
    if (label.contains('button b')) return 'button_b';
    if (label.contains('button x')) return 'button_x';
    if (label.contains('button y')) return 'button_y';
    if (label.contains('l1') || label.contains('left bumper')) return 'shoulder_l';
    if (label.contains('r1') || label.contains('right bumper')) return 'shoulder_r';
    if (label.contains('l2') || label.contains('left trigger')) return 'trigger_l';
    if (label.contains('r2') || label.contains('right trigger')) return 'trigger_r';
    if (label.contains('dpad up') || label.contains('d-pad up')) return 'dpad_up';
    if (label.contains('dpad down') || label.contains('d-pad down')) return 'dpad_down';
    if (label.contains('dpad left') || label.contains('d-pad left')) return 'dpad_left';
    if (label.contains('dpad right') || label.contains('d-pad right')) return 'dpad_right';
    if (label.contains('start') || label.contains('menu')) return 'button_start';
    if (label.contains('select') || label.contains('back') || label.contains('view')) return 'button_back';

    return null;
  }

  String _normalizeRawGamepadKey(String key) {
    final lower = key.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_').trim();
    
    // Face buttons
    if (lower == 'a' || lower == 'buttona' || lower == 'button_a' || lower == 'south' || lower == 'cross' || lower == 'button_south' || lower == 'button0') return 'button_a';
    if (lower == 'b' || lower == 'buttonb' || lower == 'button_b' || lower == 'east' || lower == 'circle' || lower == 'button_east' || lower == 'button1') return 'button_b';
    if (lower == 'x' || lower == 'buttonx' || lower == 'button_x' || lower == 'west' || lower == 'square' || lower == 'button_west' || lower == 'button2') return 'button_x';
    if (lower == 'y' || lower == 'buttony' || lower == 'button_y' || lower == 'north' || lower == 'triangle' || lower == 'button_north' || lower == 'button3') return 'button_y';

    // Bumpers / Shoulders
    if (lower == 'lb' || lower == 'l1' || lower == 'leftshoulder' || lower == 'left_shoulder' || lower == 'left_bumper' || lower == 'shoulder_l' || lower == 'button4' || lower == 'button_left_shoulder') return 'shoulder_l';
    if (lower == 'rb' || lower == 'r1' || lower == 'rightshoulder' || lower == 'right_shoulder' || lower == 'right_bumper' || lower == 'shoulder_r' || lower == 'button5' || lower == 'button_right_shoulder') return 'shoulder_r';

    // Triggers
    if (lower == 'lt' || lower == 'l2' || lower == 'lefttrigger' || lower == 'left_trigger' || lower == 'trigger_l' || lower == 'axis_lt' || lower == 'axis_l2' || lower == 'axis2' || lower == 'axis4') return 'trigger_l';
    if (lower == 'rt' || lower == 'r2' || lower == 'righttrigger' || lower == 'right_trigger' || lower == 'trigger_r' || lower == 'axis_rt' || lower == 'axis_r2' || lower == 'axis5') return 'trigger_r';

    // D-Pad
    if (lower == 'dpadup' || lower == 'dpad_up' || lower == 'dpup' || lower == 'up' || lower == 'hat0_up' || lower == 'pov_up') return 'dpad_up';
    if (lower == 'dpaddown' || lower == 'dpad_down' || lower == 'dpdown' || lower == 'down' || lower == 'hat0_down' || lower == 'pov_down') return 'dpad_down';
    if (lower == 'dpadleft' || lower == 'dpad_left' || lower == 'dpleft' || lower == 'left' || lower == 'hat0_left' || lower == 'pov_left') return 'dpad_left';
    if (lower == 'dpadright' || lower == 'dpad_right' || lower == 'dpright' || lower == 'right' || lower == 'hat0_right' || lower == 'pov_right') return 'dpad_right';

    // Thumb stick click
    if (lower == 'ls' || lower == 'l3' || lower == 'leftthumbstick' || lower == 'left_thumbstick' || lower == 'thumb_l' || lower == 'button8' || lower == 'button_thumb_l') return 'thumb_l';
    if (lower == 'rs' || lower == 'r3' || lower == 'rightthumbstick' || lower == 'right_thumbstick' || lower == 'thumb_r' || lower == 'button9' || lower == 'button_thumb_r') return 'thumb_r';

    // Start / Back / Menu
    if (lower == 'start' || lower == 'buttonstart' || lower == 'button_start' || lower == 'menu' || lower == 'options' || lower == 'button7') return 'button_start';
    if (lower == 'back' || lower == 'buttonback' || lower == 'button_back' || lower == 'select' || lower == 'view' || lower == 'share' || lower == 'button6') return 'button_back';

    // Stick axes
    if (lower == 'leftthumbstickx' || lower == 'stick_lx' || lower == 'axis_lx' || lower == 'stick_l_x' || lower == 'axis0') return 'stick_l_x';
    if (lower == 'leftthumbsticky' || lower == 'stick_ly' || lower == 'axis_ly' || lower == 'stick_l_y' || lower == 'axis1') return 'stick_l_y';
    if (lower == 'rightthumbstickx' || lower == 'stick_rx' || lower == 'axis_rx' || lower == 'stick_r_x' || lower == 'axis2' || lower == 'axis3') return 'stick_r_x';
    if (lower == 'rightthumbsticky' || lower == 'stick_ry' || lower == 'axis_ry' || lower == 'stick_r_y' || lower == 'axis3' || lower == 'axis4') return 'stick_r_y';

    return lower;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _devicePollTimer?.cancel();
    _gamepadSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    resetAllInputs(reason: 'Service disposed');
    _actionController.close();
    super.dispose();
  }
}
