import 'dart:convert';
import 'config_models.dart';

enum GamepadTriggerMode {
  singlePress,
  continuousHold,
  scaledTrigger,
}

enum GamepadActionType {
  increment,
  decrement,
  toggle,
  cycleOption,
  switchTab,
  submit,
  barcode,
  clearForm,
}

class GamepadBinding {
  final String id;
  final String inputKey; // e.g. 'button_a', 'trigger_r', 'dpad_up', etc.
  final String? customLabel;
  final GamepadActionType actionType;
  final String? targetFieldId;
  final String? targetValue; // For tabs ('auto', 'teleop', etc.) or specific option value
  final GamepadTriggerMode triggerMode;
  final String phase; // 'global', 'auto', 'teleop', 'endgame'
  final double repeatFrequencyHz; // Fixed Hz for continuousHold (e.g. 6.0 = ~166ms)
  final double triggerMinHz; // Minimum Hz for scaledTrigger (e.g. 2.0 = 500ms)
  final double triggerMaxHz; // Maximum Hz for scaledTrigger (e.g. 15.0 = ~66ms)
  final double triggerThreshold; // Deadzone threshold for trigger activation (e.g. 0.15)
  final double stepValue; // Increment/decrement amount (default 1.0)

  bool get isTrigger => isKeyTrigger(inputKey);
  bool get isRepeatable => actionType == GamepadActionType.increment || actionType == GamepadActionType.decrement;

  static bool isKeyTrigger(String key) {
    final lower = key.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return lower == 'trigger_l' ||
        lower == 'trigger_r' ||
        lower == 'l2' ||
        lower == 'r2' ||
        lower == 'lefttrigger' ||
        lower == 'righttrigger' ||
        lower == 'left_trigger' ||
        lower == 'right_trigger' ||
        lower == 'axis_lt' ||
        lower == 'axis_rt' ||
        lower == 'axis_l2' ||
        lower == 'axis_r2';
  }

  const GamepadBinding({
    required this.id,
    required this.inputKey,
    this.customLabel,
    required this.actionType,
    this.targetFieldId,
    this.targetValue,
    this.phase = 'global',
    this.triggerMode = GamepadTriggerMode.singlePress,
    this.repeatFrequencyHz = 6.0,
    this.triggerMinHz = 2.0,
    this.triggerMaxHz = 16.0,
    this.triggerThreshold = 0.15,
    this.stepValue = 1.0,
  });

  GamepadBinding copyWith({
    String? id,
    String? inputKey,
    String? customLabel,
    GamepadActionType? actionType,
    String? targetFieldId,
    String? targetValue,
    String? phase,
    GamepadTriggerMode? triggerMode,
    double? repeatFrequencyHz,
    double? triggerMinHz,
    double? triggerMaxHz,
    double? triggerThreshold,
    double? stepValue,
  }) {
    return GamepadBinding(
      id: id ?? this.id,
      inputKey: inputKey ?? this.inputKey,
      customLabel: customLabel ?? this.customLabel,
      actionType: actionType ?? this.actionType,
      targetFieldId: targetFieldId ?? this.targetFieldId,
      targetValue: targetValue ?? this.targetValue,
      phase: phase ?? this.phase,
      triggerMode: triggerMode ?? this.triggerMode,
      repeatFrequencyHz: repeatFrequencyHz ?? this.repeatFrequencyHz,
      triggerMinHz: triggerMinHz ?? this.triggerMinHz,
      triggerMaxHz: triggerMaxHz ?? this.triggerMaxHz,
      triggerThreshold: triggerThreshold ?? this.triggerThreshold,
      stepValue: stepValue ?? this.stepValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inputKey': inputKey,
      'customLabel': customLabel,
      'actionType': actionType.name,
      'targetFieldId': targetFieldId,
      'targetValue': targetValue,
      'phase': phase,
      'triggerMode': triggerMode.name,
      'repeatFrequencyHz': repeatFrequencyHz,
      'triggerMinHz': triggerMinHz,
      'triggerMaxHz': triggerMaxHz,
      'triggerThreshold': triggerThreshold,
      'stepValue': stepValue,
    };
  }

  factory GamepadBinding.fromJson(Map<String, dynamic> json) {
    return GamepadBinding(
      id: json['id'] as String? ?? 'binding_${DateTime.now().millisecondsSinceEpoch}',
      inputKey: json['inputKey'] as String? ?? 'button_a',
      customLabel: json['customLabel'] as String?,
      actionType: GamepadActionType.values.firstWhere(
        (e) => e.name == json['actionType'],
        orElse: () => GamepadActionType.increment,
      ),
      targetFieldId: json['targetFieldId'] as String?,
      targetValue: json['targetValue'] as String?,
      phase: json['phase'] as String? ?? 'global',
      triggerMode: GamepadTriggerMode.values.firstWhere(
        (e) => e.name == json['triggerMode'],
        orElse: () => GamepadTriggerMode.singlePress,
      ),
      repeatFrequencyHz: (json['repeatFrequencyHz'] as num?)?.toDouble() ?? 6.0,
      triggerMinHz: (json['triggerMinHz'] as num?)?.toDouble() ?? 2.0,
      triggerMaxHz: (json['triggerMaxHz'] as num?)?.toDouble() ?? 16.0,
      triggerThreshold: (json['triggerThreshold'] as num?)?.toDouble() ?? 0.15,
      stepValue: (json['stepValue'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class GamepadProfile {
  final String id;
  final String name;
  final String description;
  final String controllerType; // 'xbox', 'playstation', 'generic'
  final String? selectedGamepadId; // Specific gamepad ID or null for any connected
  final bool enabled;
  final bool showTooltips;
  final List<GamepadBinding> bindings;
  final DateTime updatedAt;

  GamepadProfile({
    required this.id,
    required this.name,
    this.description = '',
    this.controllerType = 'xbox',
    this.selectedGamepadId,
    this.enabled = true,
    this.showTooltips = true,
    required this.bindings,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  GamepadProfile copyWith({
    String? id,
    String? name,
    String? description,
    String? controllerType,
    String? selectedGamepadId,
    bool? enabled,
    bool? showTooltips,
    List<GamepadBinding>? bindings,
    DateTime? updatedAt,
  }) {
    return GamepadProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      controllerType: controllerType ?? this.controllerType,
      selectedGamepadId: selectedGamepadId ?? this.selectedGamepadId,
      enabled: enabled ?? this.enabled,
      showTooltips: showTooltips ?? this.showTooltips,
      bindings: bindings ?? this.bindings,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 1,
      'id': id,
      'name': name,
      'description': description,
      'controllerType': controllerType,
      'selectedGamepadId': selectedGamepadId,
      'enabled': enabled,
      'showTooltips': showTooltips,
      'updatedAt': updatedAt.toIso8601String(),
      'bindings': bindings.map((b) => b.toJson()).toList(),
    };
  }

  factory GamepadProfile.fromJson(Map<String, dynamic> json) {
    final rawBindings = json['bindings'] as List<dynamic>? ?? [];
    return GamepadProfile(
      id: json['id'] as String? ?? 'profile_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Gamepad Layout',
      description: json['description'] as String? ?? '',
      controllerType: json['controllerType'] as String? ?? 'xbox',
      selectedGamepadId: json['selectedGamepadId'] as String?,
      enabled: json['enabled'] as bool? ?? true,
      showTooltips: json['showTooltips'] as bool? ?? true,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      bindings: rawBindings
          .whereType<Map<String, dynamic>>()
          .map((b) => GamepadBinding.fromJson(b))
          .toList(),
    );
  }

  String exportJson({bool pretty = true}) {
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(toJson());
  }

  static GamepadProfile? importJson(String jsonString) {
    try {
      final decoded = json.decode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return GamepadProfile.fromJson(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Default layout presets for Xbox / PlayStation
  static GamepadProfile defaultXbox() {
    return GamepadProfile(
      id: 'default_xbox',
      name: 'Standard Xbox Layout',
      description: 'Default layout with bumper tab switching and trigger rapid fire.',
      controllerType: 'xbox',
      enabled: true,
      showTooltips: true,
      bindings: [
        // Tab switching
        const GamepadBinding(
          id: 'b_tab_prev',
          inputKey: 'shoulder_l',
          actionType: GamepadActionType.switchTab,
          targetValue: 'prev',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'b_tab_next',
          inputKey: 'shoulder_r',
          actionType: GamepadActionType.switchTab,
          targetValue: 'next',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        // Submit and Barcode
        const GamepadBinding(
          id: 'b_submit',
          inputKey: 'button_start',
          actionType: GamepadActionType.submit,
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'b_barcode',
          inputKey: 'button_back',
          actionType: GamepadActionType.barcode,
          triggerMode: GamepadTriggerMode.singlePress,
        ),
      ],
    );
  }

  static GamepadProfile defaultPlayStation() {
    return GamepadProfile(
      id: 'default_ps4',
      name: 'Standard PS4 / DualShock Layout',
      description: 'Default layout configured for PlayStation controllers.',
      controllerType: 'playstation',
      enabled: true,
      showTooltips: true,
      bindings: [
        const GamepadBinding(
          id: 'b_tab_prev_ps',
          inputKey: 'shoulder_l',
          actionType: GamepadActionType.switchTab,
          targetValue: 'prev',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'b_tab_next_ps',
          inputKey: 'shoulder_r',
          actionType: GamepadActionType.switchTab,
          targetValue: 'next',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'b_submit_ps',
          inputKey: 'button_start',
          actionType: GamepadActionType.submit,
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'b_barcode_ps',
          inputKey: 'button_back',
          actionType: GamepadActionType.barcode,
          triggerMode: GamepadTriggerMode.singlePress,
        ),
      ],
    );
  }

  static GamepadProfile defaultKeyboard() {
    return GamepadProfile(
      id: 'default_keyboard',
      name: 'Standard Computer Keyboard Layout',
      description: 'Default layout using keyboard shortcuts (Tab, Arrows, Space, Enter, Numbers).',
      controllerType: 'keyboard',
      enabled: true,
      showTooltips: true,
      bindings: [
        const GamepadBinding(
          id: 'kb_tab_prev',
          inputKey: 'key_arrow_left',
          actionType: GamepadActionType.switchTab,
          targetValue: 'prev',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'kb_tab_next',
          inputKey: 'key_arrow_right',
          actionType: GamepadActionType.switchTab,
          targetValue: 'next',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'kb_submit',
          inputKey: 'key_enter',
          actionType: GamepadActionType.submit,
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'kb_barcode',
          inputKey: 'key_b',
          actionType: GamepadActionType.barcode,
          triggerMode: GamepadTriggerMode.singlePress,
        ),
      ],
    );
  }

  /// Automatically generates an ergonomic controller mapping based on scouting form fields
  static GamepadProfile autoGenerateForConfig(
    ScoutingConfigModel config, {
    String controllerType = 'xbox',
    String? profileName,
  }) {
    final validFields = config.fields.where((f) {
      final t = f.type.toLowerCase();
      return t != 'section' && t != 'header' && t != 'divider';
    }).toList();

    // Group fields by type
    final counters = validFields.where((f) {
      final t = f.type.toLowerCase();
      return t == 'counter' || t == 'number' || t == 'stepper';
    }).toList();

    final toggles = validFields.where((f) {
      final t = f.type.toLowerCase();
      return t == 'toggle' || t == 'boolean' || t == 'checkbox';
    }).toList();

    final choices = validFields.where((f) {
      final t = f.type.toLowerCase();
      return t == 'select' || t == 'dropdown' || t == 'radio' || t == 'choice';
    }).toList();

    String resolveFieldPhase(ScoutingFieldModel f) {
      if (f.phase != null && f.phase!.isNotEmpty) {
        final p = f.phase!.toLowerCase().trim();
        if (p == 'general') return 'teleop';
        return p;
      }
      final id = f.id.toLowerCase();
      if (id.startsWith('auto')) return 'auto';
      if (id.startsWith('teleop')) return 'teleop';
      if (id.startsWith('endgame')) return 'endgame';
      if (id.startsWith('post')) return 'postmatch';
      return 'global';
    }

    if (controllerType == 'keyboard') {
      final kbBindings = <GamepadBinding>[
        const GamepadBinding(
          id: 'kb_auto_prev_tab',
          inputKey: 'key_arrow_left',
          actionType: GamepadActionType.switchTab,
          targetValue: 'prev',
          phase: 'global',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'kb_auto_next_tab',
          inputKey: 'key_arrow_right',
          actionType: GamepadActionType.switchTab,
          targetValue: 'next',
          phase: 'global',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'kb_auto_submit',
          inputKey: 'key_enter',
          actionType: GamepadActionType.submit,
          phase: 'global',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
        const GamepadBinding(
          id: 'kb_auto_barcode',
          inputKey: 'key_b',
          actionType: GamepadActionType.barcode,
          phase: 'global',
          triggerMode: GamepadTriggerMode.singlePress,
        ),
      ];

      final phases = ['auto', 'teleop', 'endgame'];
      final numKeys = ['key_1', 'key_2', 'key_3', 'key_4', 'key_5', 'key_6'];
      final decKeys = ['key_q', 'key_w', 'key_e', 'key_r', 'key_t', 'key_y'];

      for (final p in phases) {
        final phaseCounters = counters.where((c) => resolveFieldPhase(c) == p).toList();
        final phaseToggles = toggles.where((t) => resolveFieldPhase(t) == p).toList();
        final phaseChoices = choices.where((c) => resolveFieldPhase(c) == p).toList();

        for (var i = 0; i < phaseCounters.length && i < numKeys.length; i++) {
          kbBindings.add(GamepadBinding(
            id: 'kb_${p}_inc_${phaseCounters[i].id}',
            inputKey: numKeys[i],
            actionType: GamepadActionType.increment,
            targetFieldId: phaseCounters[i].id,
            phase: p,
            triggerMode: GamepadTriggerMode.continuousHold,
            repeatFrequencyHz: 6.0,
          ));
          if (i < decKeys.length) {
            kbBindings.add(GamepadBinding(
              id: 'kb_${p}_dec_${phaseCounters[i].id}',
              inputKey: decKeys[i],
              actionType: GamepadActionType.decrement,
              targetFieldId: phaseCounters[i].id,
              phase: p,
              triggerMode: GamepadTriggerMode.continuousHold,
              repeatFrequencyHz: 5.0,
            ));
          }
        }

        if (phaseToggles.isNotEmpty) {
          kbBindings.add(GamepadBinding(
            id: 'kb_${p}_toggle_${phaseToggles[0].id}',
            inputKey: 'key_space',
            actionType: GamepadActionType.toggle,
            targetFieldId: phaseToggles[0].id,
            phase: p,
            triggerMode: GamepadTriggerMode.singlePress,
          ));
        }
        if (phaseToggles.length > 1) {
          kbBindings.add(GamepadBinding(
            id: 'kb_${p}_toggle_${phaseToggles[1].id}',
            inputKey: 'key_z',
            actionType: GamepadActionType.toggle,
            targetFieldId: phaseToggles[1].id,
            phase: p,
            triggerMode: GamepadTriggerMode.singlePress,
          ));
        }

        final choiceKeys = ['key_c', 'key_v', 'key_x'];
        for (var i = 0; i < phaseChoices.length && i < choiceKeys.length; i++) {
          kbBindings.add(GamepadBinding(
            id: 'kb_${p}_choice_${phaseChoices[i].id}',
            inputKey: choiceKeys[i],
            actionType: GamepadActionType.cycleOption,
            targetFieldId: phaseChoices[i].id,
            phase: p,
            triggerMode: GamepadTriggerMode.singlePress,
          ));
        }
      }

      // If no phase-specific fields matched, fallback to general
      if (kbBindings.length <= 4) {
        for (var i = 0; i < counters.length && i < numKeys.length; i++) {
          kbBindings.add(GamepadBinding(
            id: 'kb_inc_${counters[i].id}',
            inputKey: numKeys[i],
            actionType: GamepadActionType.increment,
            targetFieldId: counters[i].id,
            phase: 'global',
            triggerMode: GamepadTriggerMode.continuousHold,
            repeatFrequencyHz: 6.0,
          ));
        }
      }

      return GamepadProfile(
        id: 'auto_gen_kb_${DateTime.now().millisecondsSinceEpoch}',
        name: profileName ?? 'Smart Keyboard Layout',
        description: 'Auto-generated period-aware keyboard layout mapped to number keys, shortcuts, and spacebar.',
        controllerType: 'keyboard',
        enabled: true,
        showTooltips: true,
        bindings: kbBindings,
      );
    }

    final newBindings = <GamepadBinding>[];

    // 1. SYSTEM ACTIONS -> Global Across All Periods
    newBindings.add(const GamepadBinding(
      id: 'auto_gen_lb',
      inputKey: 'shoulder_l',
      actionType: GamepadActionType.switchTab,
      targetValue: 'prev',
      phase: 'global',
      triggerMode: GamepadTriggerMode.singlePress,
    ));
    newBindings.add(const GamepadBinding(
      id: 'auto_gen_rb',
      inputKey: 'shoulder_r',
      actionType: GamepadActionType.switchTab,
      targetValue: 'next',
      phase: 'global',
      triggerMode: GamepadTriggerMode.singlePress,
    ));
    newBindings.add(const GamepadBinding(
      id: 'auto_gen_start',
      inputKey: 'button_start',
      actionType: GamepadActionType.submit,
      phase: 'global',
      triggerMode: GamepadTriggerMode.singlePress,
    ));
    newBindings.add(const GamepadBinding(
      id: 'auto_gen_back',
      inputKey: 'button_back',
      actionType: GamepadActionType.barcode,
      phase: 'global',
      triggerMode: GamepadTriggerMode.singlePress,
    ));

    // 2. PERIOD-SPECIFIC FIELD BINDINGS
    void bindPhase(String phase) {
      final phaseCounters = counters.where((c) => resolveFieldPhase(c) == phase).toList();
      final phaseToggles = toggles.where((t) => resolveFieldPhase(t) == phase).toList();
      final phaseChoices = choices.where((c) => resolveFieldPhase(c) == phase).toList();

      if (phaseCounters.isNotEmpty) {
        final primaryCounter = phaseCounters[0];
        // RT -> Primary Counter Increment with Trigger Scaling
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_rt',
          inputKey: 'trigger_r',
          actionType: GamepadActionType.increment,
          targetFieldId: primaryCounter.id,
          phase: phase,
          triggerMode: GamepadTriggerMode.scaledTrigger,
          triggerMinHz: 2.0,
          triggerMaxHz: 16.0,
        ));

        // LT -> Secondary Counter Increment or Primary Decrement
        if (phaseCounters.length > 1) {
          final secondaryCounter = phaseCounters[1];
          newBindings.add(GamepadBinding(
            id: '${phase}_gen_lt',
            inputKey: 'trigger_l',
            actionType: GamepadActionType.increment,
            targetFieldId: secondaryCounter.id,
            phase: phase,
            triggerMode: GamepadTriggerMode.scaledTrigger,
            triggerMinHz: 2.0,
            triggerMaxHz: 14.0,
          ));
        } else {
          newBindings.add(GamepadBinding(
            id: '${phase}_gen_lt_dec',
            inputKey: 'trigger_l',
            actionType: GamepadActionType.decrement,
            targetFieldId: primaryCounter.id,
            phase: phase,
            triggerMode: GamepadTriggerMode.scaledTrigger,
            triggerMinHz: 2.0,
            triggerMaxHz: 12.0,
          ));
        }
      }

      // Button Y: 3rd counter or primary decrement
      if (phaseCounters.length > 2) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_btn_y',
          inputKey: 'button_y',
          actionType: GamepadActionType.increment,
          targetFieldId: phaseCounters[2].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.continuousHold,
          repeatFrequencyHz: 6.0,
        ));
      } else if (phaseCounters.isNotEmpty && !newBindings.any((b) => b.phase == phase && b.inputKey == 'trigger_l' && b.actionType == GamepadActionType.decrement)) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_btn_y',
          inputKey: 'button_y',
          actionType: GamepadActionType.decrement,
          targetFieldId: phaseCounters[0].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.continuousHold,
          repeatFrequencyHz: 5.0,
        ));
      }

      // Button X: 4th counter or secondary decrement
      if (phaseCounters.length > 3) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_btn_x',
          inputKey: 'button_x',
          actionType: GamepadActionType.increment,
          targetFieldId: phaseCounters[3].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.continuousHold,
          repeatFrequencyHz: 6.0,
        ));
      } else if (phaseCounters.length > 1) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_btn_x',
          inputKey: 'button_x',
          actionType: GamepadActionType.decrement,
          targetFieldId: phaseCounters[1].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.continuousHold,
          repeatFrequencyHz: 5.0,
        ));
      }

      // Button A: Primary Phase Toggle
      if (phaseToggles.isNotEmpty) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_btn_a',
          inputKey: 'button_a',
          actionType: GamepadActionType.toggle,
          targetFieldId: phaseToggles[0].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.singlePress,
        ));
      }

      // Button B: Primary Phase Choice / Dropdown cycle (or 2nd toggle)
      if (phaseChoices.isNotEmpty) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_btn_b',
          inputKey: 'button_b',
          actionType: GamepadActionType.cycleOption,
          targetFieldId: phaseChoices[0].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.singlePress,
        ));
      } else if (phaseToggles.length > 1) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_btn_b',
          inputKey: 'button_b',
          actionType: GamepadActionType.toggle,
          targetFieldId: phaseToggles[1].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.singlePress,
        ));
      }

      // D-Pad Up / Down / Left / Right for remaining fields in phase
      if (phaseCounters.length > 4) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_dpad_up',
          inputKey: 'dpad_up',
          actionType: GamepadActionType.increment,
          targetFieldId: phaseCounters[4].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.continuousHold,
          repeatFrequencyHz: 5.0,
        ));
      }
      if (phaseCounters.length > 5) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_dpad_down',
          inputKey: 'dpad_down',
          actionType: GamepadActionType.increment,
          targetFieldId: phaseCounters[5].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.continuousHold,
          repeatFrequencyHz: 5.0,
        ));
      }
      if (phaseToggles.length > 2) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_dpad_left',
          inputKey: 'dpad_left',
          actionType: GamepadActionType.toggle,
          targetFieldId: phaseToggles[2].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.singlePress,
        ));
      }
      if (phaseChoices.length > 1) {
        newBindings.add(GamepadBinding(
          id: '${phase}_gen_dpad_right',
          inputKey: 'dpad_right',
          actionType: GamepadActionType.cycleOption,
          targetFieldId: phaseChoices[1].id,
          phase: phase,
          triggerMode: GamepadTriggerMode.singlePress,
        ));
      }
    }

    bindPhase('auto');
    bindPhase('teleop');
    bindPhase('endgame');

    // If no phase-specific bindings were generated, fallback to global bindings
    if (newBindings.length <= 4 && (counters.isNotEmpty || toggles.isNotEmpty || choices.isNotEmpty)) {
      if (counters.isNotEmpty) {
        newBindings.add(GamepadBinding(
          id: 'global_gen_rt',
          inputKey: 'trigger_r',
          actionType: GamepadActionType.increment,
          targetFieldId: counters[0].id,
          phase: 'global',
          triggerMode: GamepadTriggerMode.scaledTrigger,
        ));
      }
    }

    return GamepadProfile(
      id: 'auto_gen_${DateTime.now().millisecondsSinceEpoch}',
      name: profileName ?? (controllerType == 'playstation' ? 'Smart PS4 Layout' : 'Smart Xbox Layout'),
      description: 'Auto-generated smart layout mapped to form elements & controller ergonomics.',
      controllerType: controllerType,
      enabled: true,
      showTooltips: true,
      bindings: newBindings,
    );
  }
}

class GamepadActionEvent {
  final GamepadBinding binding;
  final double value;
  final bool isRepeat;
  final DateTime timestamp;

  GamepadActionEvent({
    required this.binding,
    required this.value,
    this.isRepeat = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
