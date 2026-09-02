import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zxing_lib/common.dart' as zxing_common;
import 'package:zxing_lib/qrcode.dart' as zxing_qr;
import 'package:zxing_lib/zxing.dart' as zxing;
import '../l10n/app_localizations.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/obsidian_barcode_modal.dart';
import '../widgets/obsidian_feedback.dart';
import '../services/api_service.dart';
import '../services/scout_history_service.dart';

class ScannedQueueItem {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  String status; // "pending", "success", "error"
  String errorMsg;

  ScannedQueueItem({
    required this.id,
    required this.type,
    required this.data,
    this.status = 'pending',
    this.errorMsg = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'data': data,
        'status': status,
        'errorMsg': errorMsg,
      };

  factory ScannedQueueItem.fromJson(Map<String, dynamic> json) {
    return ScannedQueueItem(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      data: (json['data'] is Map) ? Map<String, dynamic>.from(json['data'] as Map) : {},
      status: json['status']?.toString() ?? 'pending',
      errorMsg: json['errorMsg']?.toString() ?? '',
    );
  }
}

class QrScannerScreen extends StatefulWidget {
  final ApiService apiService;

  const QrScannerScreen({super.key, required this.apiService});

  /// Unpacks an alliance QR bundle (whether wrapped in `{type, data}` envelope or raw) into individual team entries.
  static List<Map<String, dynamic>> unpackAllianceBundle(dynamic decoded) {
    if (decoded == null) return [];

    final bundleMap = (decoded is Map<String, dynamic> && decoded['data'] is Map<String, dynamic> && ((decoded['data'] as Map)['type'] == 'qual-alliance' || (decoded['data'] as Map)['entries'] is List))
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : (decoded is Map<String, dynamic> ? decoded : <String, dynamic>{});

    final bool isAllianceBundle = bundleMap['type'] == 'qual-alliance' ||
        (decoded is Map<String, dynamic> && decoded['type'] == 'qual-alliance') ||
        bundleMap['entries'] is List;

    if (!isAllianceBundle) return [];

    final rawEntries = bundleMap['entries'] ?? (decoded is Map<String, dynamic> ? decoded['entries'] : null);
    final entriesList = (rawEntries is List) ? rawEntries : [];
    final results = <Map<String, dynamic>>[];

    for (final item in entriesList) {
      if (item is Map) {
        final itemMap = Map<String, dynamic>.from(item);
        final entryPayload = itemMap['data'] is Map ? Map<String, dynamic>.from(itemMap['data'] as Map) : itemMap;
        final dynamic rawTeamNum = entryPayload['targetTeamNumber'] ?? entryPayload['teamNumber'];
        final int? teamNum = rawTeamNum is num ? rawTeamNum.toInt() : (rawTeamNum != null ? int.tryParse(rawTeamNum.toString()) : null);

        if (teamNum != null && teamNum > 0) {
          entryPayload['targetTeamNumber'] = teamNum;
          if (entryPayload['eventKey'] == null && bundleMap['eventKey'] != null) {
            entryPayload['eventKey'] = bundleMap['eventKey'];
          }
          if (entryPayload['matchKey'] == null && bundleMap['matchKey'] != null) {
            entryPayload['matchKey'] = bundleMap['matchKey'];
          }
          if (entryPayload['matchNumber'] == null && bundleMap['matchNumber'] != null) {
            entryPayload['matchNumber'] = bundleMap['matchNumber'];
          }
          if (entryPayload['type'] == null || entryPayload['type'] == 'qual-alliance') {
            entryPayload['type'] = 'qual-scout';
          }
          results.add(entryPayload);
        }
      }
    }
    return results;
  }

  @override
  State<QrScannerScreen> createState() => QrScannerScreenState();
}

class QrScannerScreenState extends State<QrScannerScreen> with WidgetsBindingObserver {
  @visibleForTesting
  void handleRawScan(String rawText, {bool resetCooldown = false}) {
    if (resetCooldown) {
      _lastScannedText = null;
      _lastScanTime = null;
      _isProcessingScan = false;
    }
    _handleRawScan(rawText);
  }

  @visibleForTesting
  List<ScannedQueueItem> get queue => _queue;
  late final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.all],
  );
  final TextEditingController _manualInputController = TextEditingController();

  List<ScannedQueueItem> _queue = [];
  bool _isScanning = true;
  bool _isUploading = false;
  bool _showManualInput = false;

  bool get _isDesktopWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows && !Platform.environment.containsKey('FLUTTER_TEST');
  List<CameraDescription> _availableCameras = [];
  CameraController? _desktopCameraController;
  int _selectedCameraIndex = 0;
  Timer? _desktopScanTimer;
  bool _isInitializingCamera = false;
  String? _cameraErrorMessage;

  bool _hasCameraPermission = true;
  bool _isPermanentlyDenied = false;
  bool _isCheckingPermission = false;

  static const String _storageKey = 'obsidianscout:scanned_qr_entries';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadQueue();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      if (_isDesktopWindows) {
        _initDesktopCamera();
      } else {
        _checkAndRequestPermission(directRequest: true);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDesktopWindows) return;
    if (state == AppLifecycleState.resumed) {
      _checkAndRequestPermission(directRequest: false);
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      try {
        _scannerController.stop();
      } catch (_) {}
    }
  }

  Future<void> _checkAndRequestPermission({bool directRequest = true}) async {
    if (_isDesktopWindows) return;

    setState(() {
      _isCheckingPermission = true;
    });

    try {
      final status = await Permission.camera.status;
      if (status.isGranted || status.isLimited) {
        if (mounted) {
          setState(() {
            _hasCameraPermission = true;
            _isPermanentlyDenied = false;
            _isCheckingPermission = false;
          });
          if (_isScanning) {
            try {
              await _scannerController.start();
            } catch (_) {}
          }
        }
        return;
      }

      if (directRequest) {
        final reqResult = await Permission.camera.request();
        if (reqResult.isGranted || reqResult.isLimited) {
          if (mounted) {
            setState(() {
              _hasCameraPermission = true;
              _isPermanentlyDenied = false;
              _isCheckingPermission = false;
            });
            if (_isScanning) {
              try {
                await _scannerController.start();
              } catch (_) {}
            }
          }
          return;
        }

        if (mounted) {
          setState(() {
            _hasCameraPermission = false;
            _isPermanentlyDenied = reqResult.isPermanentlyDenied;
            _isCheckingPermission = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasCameraPermission = status.isGranted || status.isLimited;
            _isPermanentlyDenied = status.isPermanentlyDenied;
            _isCheckingPermission = false;
          });
          if ((status.isGranted || status.isLimited) && _isScanning) {
            try {
              await _scannerController.start();
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingPermission = false;
        });
      }
    }
  }

  String _formatCameraName(String rawName) {
    if (rawName.isEmpty) return 'Camera';
    if (rawName.contains('<')) {
      final idx = rawName.indexOf('<');
      final prefix = rawName.substring(0, idx).trim();
      if (prefix.isNotEmpty) return prefix;
    }
    if (rawName.contains('#')) {
      final parts = rawName.split('#');
      if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
        return parts[0].trim();
      }
    }
    return rawName;
  }

  Future<void> _initDesktopCamera() async {
    if (!_isDesktopWindows) return;

    setState(() {
      _isInitializingCamera = true;
      _cameraErrorMessage = null;
    });

    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isNotEmpty) {
        bool foundWorking = false;
        for (int i = 0; i < _availableCameras.length; i++) {
          final success = await _tryInitCameraIndex(i);
          if (success) {
            foundWorking = true;
            break;
          }
        }
        if (!foundWorking && mounted) {
          setState(() {
            _cameraErrorMessage = 'Could not start any connected webcams (try selecting a camera from the dropdown)';
            _isInitializingCamera = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _cameraErrorMessage = 'No camera devices detected on this computer';
            _isInitializingCamera = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Failed to access camera hardware: $e';
        if (e is MissingPluginException || e.toString().contains('MissingPluginException')) {
          msg = 'Native Windows camera plugin registered!\nPlease perform a full app restart ("flutter run -d windows") to link camera DLL.';
        }
        setState(() {
          _cameraErrorMessage = msg;
          _isInitializingCamera = false;
        });
      }
    }
  }

  Future<bool> _tryInitCameraIndex(int index) async {
    if (index < 0 || index >= _availableCameras.length) return false;

    _desktopScanTimer?.cancel();
    if (_desktopCameraController != null) {
      final old = _desktopCameraController!;
      _desktopCameraController = null;
      try {
        await old.dispose();
      } catch (_) {}
    }

    final camera = _availableCameras[index];
    _selectedCameraIndex = index;

    final presetsToTry = [
      ResolutionPreset.low,
      ResolutionPreset.medium,
      ResolutionPreset.high,
      ResolutionPreset.veryHigh,
    ];

    CameraController? controller;
    Object? lastError;

    for (final preset in presetsToTry) {
      final tempController = CameraController(
        camera,
        preset,
        enableAudio: false,
      );
      try {
        await tempController.initialize();
        controller = tempController;
        break;
      } catch (err) {
        lastError = err;
        try {
          await tempController.dispose();
        } catch (_) {}
      }
    }

    if (controller != null && controller.value.isInitialized) {
      if (!mounted) {
        try {
          await controller.dispose();
        } catch (_) {}
        return false;
      }
      setState(() {
        _desktopCameraController = controller;
        _isInitializingCamera = false;
        _cameraErrorMessage = null;
      });
      _startDesktopScanningLoop();
      return true;
    } else {
      if (mounted) {
        final errText = lastError is CameraException ? (lastError.description ?? lastError.code) : (lastError?.toString() ?? 'Failed to initialize preview');
        setState(() {
          _cameraErrorMessage = 'Camera (${_formatCameraName(camera.name)}) error: $errText';
          _isInitializingCamera = false;
        });
      }
      return false;
    }
  }

  Future<void> _selectCameraIndex(int index) async {
    setState(() {
      _isInitializingCamera = true;
      _cameraErrorMessage = null;
    });
    await _tryInitCameraIndex(index);
  }

  Future<String?> _decodeQrFromImageFile(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final decodedImage = img.decodeImage(bytes);
      if (decodedImage == null) return null;

      final width = decodedImage.width;
      final height = decodedImage.height;

      final Uint8List luminancePixels = Uint8List(width * height);
      int index = 0;
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = decodedImage.getPixel(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          luminancePixels[index++] = (r * 299 + g * 587 + b * 114) ~/ 1000;
        }
      }

      final source = zxing.RGBLuminanceSource.orig(width, height, luminancePixels);
      final binarizer = zxing_common.HybridBinarizer(source);
      final bitmap = zxing.BinaryBitmap(binarizer);

      final reader = zxing_qr.QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text;
    } catch (_) {
      return null;
    }
  }

  bool _isFrameDecoding = false;

  void _startDesktopScanningLoop() {
    _desktopScanTimer?.cancel();
    _desktopScanTimer = Timer.periodic(const Duration(milliseconds: 900), (_) async {
      if (_isFrameDecoding || !_isScanning || _isProcessingScan || _desktopCameraController == null || !_desktopCameraController!.value.isInitialized) {
        return;
      }
      _isFrameDecoding = true;
      try {
        final xfile = await _desktopCameraController!.takePicture();
        final decodedText = await _decodeQrFromImageFile(xfile.path);
        try {
          final file = File(xfile.path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}

        if (decodedText != null && decodedText.isNotEmpty) {
          _handleRawScan(decodedText);
        }
      } catch (_) {
      } finally {
        _isFrameDecoding = false;
      }
    });
  }

  Future<void> _safeToggleTorch() async {
    try {
      await _scannerController.toggleTorch();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flashlight control unavailable on this device'),
            backgroundColor: ObsidianUITheme.warningOrange,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _safeSwitchCamera() async {
    if (_isDesktopWindows) {
      if (_availableCameras.length > 1) {
        final nextIdx = (_selectedCameraIndex + 1) % _availableCameras.length;
        _selectCameraIndex(nextIdx);
      }
      return;
    }

    try {
      await _scannerController.switchCamera();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera switching unavailable on this device'),
            backgroundColor: ObsidianUITheme.warningOrange,
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _desktopScanTimer?.cancel();
    _desktopCameraController?.dispose();
    _scannerController.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = jsonDecode(raw);
        setState(() {
          _queue = list.map((item) => ScannedQueueItem.fromJson(item as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_queue.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, raw);
    } catch (_) {}
  }

  bool _isProcessingScan = false;
  int? _activeMultiTotal;
  final Map<int, String> _activeMultiParts = {};

  void _cancelMultiPartScan() {
    setState(() {
      _activeMultiTotal = null;
      _activeMultiParts.clear();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Multi-part QR scan cancelled'),
          backgroundColor: ObsidianUITheme.warningOrange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String? _lastScannedText;
  DateTime? _lastScanTime;

  void _handleRawScan(String rawText) async {
    if (rawText.isEmpty || _isProcessingScan) return;

    final now = DateTime.now();
    if (_lastScannedText == rawText && _lastScanTime != null && now.difference(_lastScanTime!).inMilliseconds < 1200) {
      return;
    }

    _isProcessingScan = true;
    _lastScannedText = rawText;
    _lastScanTime = now;
    int coolDownMs = 1000;

    try {
      HapticFeedback.vibrate();
      final trimmed = rawText.trim();
      String decompressed = '';

      if (trimmed.startsWith('OSC:PART:')) {
        final parts = trimmed.split(':');
        if (parts.length >= 5) {
          final index = int.tryParse(parts[2]) ?? 1;
          final total = int.tryParse(parts[3]) ?? 1;
          final chunk = parts.sublist(4).join(':');

          if (_activeMultiTotal != total) {
            _activeMultiTotal = total;
            _activeMultiParts.clear();
          }

          if (_activeMultiParts.containsKey(index)) {
            coolDownMs = 400;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Part $index already scanned. Scan remaining part(s).'),
                  backgroundColor: ObsidianUITheme.warningOrange,
                  duration: const Duration(seconds: 1),
                ),
              );
            }
            return;
          }

          _activeMultiParts[index] = chunk;
          setState(() {});

          if (_activeMultiParts.length < total) {
            coolDownMs = 400;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Scanned Part $index of $total! Scan remaining part(s).'),
                  backgroundColor: ObsidianUITheme.warningOrange,
                  duration: const Duration(seconds: 1),
                ),
              );
            }
            return;
          }

          // All parts received! Assemble base64 payload
          final List<String> sortedChunks = [];
          for (int i = 1; i <= total; i++) {
            sortedChunks.add(_activeMultiParts[i] ?? '');
          }
          final assembledBase64 = sortedChunks.join('');
          _activeMultiTotal = null;
          _activeMultiParts.clear();

          decompressed = BarcodeCompressor.decompressData('OSC:$assembledBase64');
        } else {
          decompressed = BarcodeCompressor.decompressData(trimmed);
        }
      } else {
        decompressed = BarcodeCompressor.decompressData(trimmed);
      }

      final dynamic decoded = jsonDecode(decompressed);

      // Handle Alliance-Level Scouting QR Codes (contains multiple team entries)
      final allianceEntries = QrScannerScreen.unpackAllianceBundle(decoded);
      if (allianceEntries.isNotEmpty) {
        final bundleMap = (decoded is Map<String, dynamic> && decoded['data'] is Map<String, dynamic>)
            ? Map<String, dynamic>.from(decoded['data'] as Map)
            : (decoded is Map<String, dynamic> ? decoded : <String, dynamic>{});
        final allianceScope = bundleMap['scope']?.toString() ?? (decoded is Map ? decoded['scope']?.toString() : null) ?? 'Alliance';
        int added = 0;
        int alreadyInQueue = 0;
        final teamNumbers = <int>[];

        for (final entryPayload in allianceEntries) {
          final int teamNum = entryPayload['targetTeamNumber'] as int;
          final isDup = _queue.any((q) =>
              (q.type == 'qual-scout' || q.type == 'qualitative-scouting') &&
              q.data['eventKey']?.toString() == entryPayload['eventKey']?.toString() &&
              q.data['targetTeamNumber']?.toString() == teamNum.toString() &&
              q.data['matchKey']?.toString() == entryPayload['matchKey']?.toString());

          if (!isDup) {
            final newItem = ScannedQueueItem(
              id: '${DateTime.now().millisecondsSinceEpoch}_${teamNum}_$added',
              type: 'qual-scout',
              data: entryPayload,
              status: 'pending',
            );
            _queue.add(newItem);
            teamNumbers.add(teamNum);
            added++;
            ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
              type: 'qual',
              action: 'qr_scanned',
              status: 'pending',
              payload: entryPayload,
            ));
          } else {
            alreadyInQueue++;
          }
        }

        _saveQueue();
        setState(() {});

        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          if (added > 0) {
            final extra = alreadyInQueue > 0 ? ' ($alreadyInQueue already in queue)' : '';
            messenger.showSnackBar(
              SnackBar(
                content: Text('Scanned $allianceScope: ${teamNumbers.join(', ')} ($added entries added$extra)'),
                backgroundColor: ObsidianUITheme.successGreen,
                duration: const Duration(seconds: 2),
              ),
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text('All ${allianceEntries.length} alliance entries already exist in queue'),
                backgroundColor: ObsidianUITheme.warningOrange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
        return;
      }

      final Map<String, dynamic> parsed = decoded is Map<String, dynamic> ? decoded : {};

      final String? type = parsed['type']?.toString();
      final rawData = parsed['data'];
      Map<String, dynamic> payload = {};

      if (rawData is Map<String, dynamic>) {
        payload = rawData;
      } else if (parsed.containsKey('targetTeamNumber') || parsed.containsKey('eventKey')) {
        payload = parsed;
      }

      if (type == null && payload.isEmpty) {
        throw const FormatException('Invalid ObsidianScout QR schema');
      }

      final formType = type ?? 'match-scout';

      // Check for duplicate
      final isDuplicate = _queue.any((item) =>
          item.type == formType &&
          item.data['eventKey'] == payload['eventKey'] &&
          item.data['targetTeamNumber'] == payload['targetTeamNumber'] &&
          item.data['matchKey'] == payload['matchKey']);

      if (isDuplicate) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Entry already exists in queue'),
              backgroundColor: ObsidianUITheme.warningOrange,
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      final newItem = ScannedQueueItem(
        id: '${DateTime.now().millisecondsSinceEpoch}_${payload['targetTeamNumber'] ?? '0'}',
        type: formType,
        data: payload,
        status: 'pending',
      );

      setState(() {
        _queue.add(newItem);
      });
      _saveQueue();

      ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
        type: formType.contains('pit') ? 'pit' : (formType.contains('qual') ? 'qual' : (formType.contains('prescout') ? 'prescout-match' : 'match')),
        action: 'qr_scanned',
        status: 'pending',
        payload: payload,
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scanned: Team ${payload['targetTeamNumber'] ?? 'Unknown'} (${_getFormTypeLabel(formType)})'),
            backgroundColor: ObsidianUITheme.successGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR code is not a valid ObsidianScout entry'),
            backgroundColor: ObsidianUITheme.errorRed,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      await Future.delayed(Duration(milliseconds: coolDownMs));
      if (mounted) {
        setState(() {
          _isProcessingScan = false;
        });
      }
    }
  }

  Future<void> _uploadQueue() async {
    final pendingItems = _queue.where((item) => item.status == 'pending' || item.status == 'error').toList();
    if (pendingItems.isEmpty) return;

    setState(() => _isUploading = true);

    int successCount = 0;
    int failCount = 0;
    String? lastErrorMsg;
    int? lastErrorCode;

    for (final item in pendingItems) {
      final response = await widget.apiService.submitScannedItem(item.type, item.data);
      if (response.success) {
        setState(() {
          item.status = 'success';
          item.errorMsg = '';
        });
        ScoutHistoryService.addEntry(ScoutHistoryService.buildEntry(
          type: item.type.contains('pit') ? 'pit' : (item.type.contains('qual') ? 'qual' : (item.type.contains('prescout') ? 'prescout-match' : 'match')),
          action: 'qr_scanned',
          status: 'synced',
          payload: item.data,
        ));
        successCount++;
      } else {
        final errorText = response.statusCode != null
            ? 'HTTP ${response.statusCode}${response.message != null && response.message!.isNotEmpty ? ": ${response.message!}" : ""}'
            : (response.isOffline ? 'Offline' : (response.message ?? 'Upload failed'));
        setState(() {
          item.status = 'error';
          item.errorMsg = errorText;
        });
        lastErrorMsg = errorText;
        lastErrorCode = response.statusCode;
        failCount++;
      }
      await _saveQueue();
    }

    setState(() => _isUploading = false);

    if (mounted) {
      if (successCount > 0 && failCount == 0) {
        ObsidianFeedback.showSuccess(
          context,
          title: 'Upload Successful',
          message: 'Successfully uploaded $successCount entries to server!',
        );
      } else if (failCount > 0 && successCount == 0) {
        ObsidianFeedback.showError(
          context,
          title: 'Upload Failed',
          message: 'Failed to upload $failCount entries ($lastErrorMsg)',
          statusCode: lastErrorCode,
        );
      } else if (failCount > 0 && successCount > 0) {
        ObsidianFeedback.showWarning(
          context,
          title: 'Partial Upload Complete',
          message: 'Uploaded $successCount entries. Failed to upload $failCount entries ($lastErrorMsg)',
        );
      }
    }
  }

  void _clearQueue() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.surface,
        title: const Text('Clear Queue', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to clear all scanned items in queue?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _queue.clear());
              _saveQueue();
            },
            child: const Text('Clear All', style: TextStyle(color: ObsidianUITheme.errorRed)),
          ),
        ],
      ),
    );
  }

  void _removeQueueItem(String id) {
    setState(() {
      _queue.removeWhere((item) => item.id == id);
    });
    _saveQueue();
  }

  String _getFormTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'scout':
      case 'match-scout':
      case 'match-scouting':
        return 'Match Scouting';
      case 'pit-scout':
      case 'pit-scouting':
        return 'Pit Scouting';
      case 'qual-scout':
      case 'qualitative-scouting':
      case 'qual-scouting':
      case 'qual-alliance':
        return 'Qual Scouting';
      case 'prescout-scout':
        return 'Match Prescouting';
      case 'prescout-pit':
        return 'Pit Prescouting';
      case 'prescout-qual':
        return 'Qual Prescouting';
      default:
        return type;
    }
  }

  Widget _buildMultiPartProgressCard() {
    if (_activeMultiTotal == null) return const SizedBox.shrink();
    final total = _activeMultiTotal!;
    final scannedCount = _activeMultiParts.length;
    final isComplete = scannedCount == total;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: ObsidianGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isComplete ? 'Multi-Part Entry Complete!' : 'Multi-Part Scan ($scannedCount of $total Scanned)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isComplete ? ObsidianUITheme.successGreen : ObsidianUITheme.getPrimaryTextColor(context),
                          fontSize: 14.0,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        isComplete ? 'Assembling entry...' : 'Scan remaining parts in any order',
                        style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11.0),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: ObsidianUITheme.errorRed,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.cancel_rounded, size: 16),
                  label: const Text('Cancel', style: TextStyle(fontSize: 12.0)),
                  onPressed: _cancelMultiPartScan,
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: List.generate(total, (idx) {
                final partNum = idx + 1;
                final isDone = _activeMultiParts.containsKey(partNum);
                final color = isDone ? ObsidianUITheme.successGreen : ObsidianUITheme.getTertiaryTextColor(context);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: isDone ? ObsidianUITheme.successGreen.withValues(alpha: 0.2) : ObsidianUITheme.getBorderColor(context),
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: color),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isDone ? Icons.check_circle_rounded : Icons.pending_rounded, size: 14.0, color: color),
                      const SizedBox(width: 4.0),
                      Text(
                        'Part $partNum ${isDone ? "(Scanned)" : "(Pending)"}',
                        style: TextStyle(color: color, fontSize: 11.0, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedCard(Color borderColor, Color primaryTextColor) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(20.0),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography_rounded, color: ObsidianUITheme.warningOrange, size: 40),
              const SizedBox(height: 10),
              const Text(
                'Camera Permission Required',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _isPermanentlyDenied
                    ? 'Camera permission is permanently denied. Please enable camera access in device settings to scan QR codes.'
                    : 'ObsidianScout needs camera permission to scan scouting barcodes.',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ObsidianUITheme.primaryAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    onPressed: () async {
                      if (_isPermanentlyDenied) {
                        await openAppSettings();
                      } else {
                        await _checkAndRequestPermission(directRequest: true);
                      }
                    },
                    icon: Icon(_isPermanentlyDenied ? Icons.settings_rounded : Icons.lock_open_rounded, size: 16),
                    label: Text(
                      _isPermanentlyDenied ? 'Open App Settings' : 'Grant Camera Access',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: borderColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: _pasteFromClipboard,
                    icon: Icon(Icons.assignment_turned_in_rounded, size: 16, color: primaryTextColor),
                    label: Text('Paste Clipboard', style: TextStyle(fontSize: 12, color: primaryTextColor)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraDeviceSelector() {
    if (_isDesktopWindows && _availableCameras.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: ObsidianUITheme.getInputFillColor(context),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
        ),
        child: Row(
          children: [
            const Icon(Icons.videocam_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedCameraIndex,
                  isExpanded: true,
                  dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                  style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13.0),
                  items: List.generate(_availableCameras.length, (idx) {
                    final cam = _availableCameras[idx];
                    final name = _formatCameraName(cam.name);
                    return DropdownMenuItem<int>(
                      value: idx,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    );
                  }),
                  onChanged: (newIdx) {
                    if (newIdx != null) {
                      _selectCameraIndex(newIdx);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
        _handleRawScan(data.text!.trim());
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clipboard is empty or contains no text data'),
              backgroundColor: ObsidianUITheme.warningOrange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read clipboard: $e'),
            backgroundColor: ObsidianUITheme.errorRed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _queue.where((i) => i.status == 'pending' || i.status == 'error').length;
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('scanner.title'), style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor)),
        backgroundColor: scaffoldBg,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_returned_rounded, color: ObsidianUITheme.primaryAccent),
            tooltip: 'Paste from Clipboard (PC)',
            onPressed: _pasteFromClipboard,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: secondaryTextColor),
            tooltip: 'Restart Camera Preview',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (_isDesktopWindows) {
                await _selectCameraIndex(_selectedCameraIndex);
              } else {
                await _checkAndRequestPermission(directRequest: true);
                if (_hasCameraPermission) {
                  try {
                    await _scannerController.stop();
                    await _scannerController.start();
                  } catch (_) {}
                }
              }
              setState(() {
                _isProcessingScan = false;
                _lastScannedText = null;
              });
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Camera preview restarted'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(_showManualInput ? Icons.camera_alt_rounded : Icons.keyboard_rounded, color: secondaryTextColor),
            tooltip: _showManualInput ? 'Use Camera' : 'Manual Code / Clipboard Input',
            onPressed: () => setState(() => _showManualInput = !_showManualInput),
          ),
        ],
      ),
      backgroundColor: scaffoldBg,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMultiPartProgressCard(),
            // Camera / Viewfinder Card
            ObsidianGlassCard(
              child: Column(
                children: [
                  _buildCameraDeviceSelector(),
                  if (!_showManualInput) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16.0),
                      child: SizedBox(
                        height: 340,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_isDesktopWindows) ...[
                              if (_isInitializingCamera)
                                const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent))
                              else if (_desktopCameraController != null && _desktopCameraController!.value.isInitialized)
                                Center(
                                  child: AspectRatio(
                                    aspectRatio: _desktopCameraController!.value.aspectRatio,
                                    child: CameraPreview(_desktopCameraController!),
                                  ),
                                )
                              else
                                Container(
                                  color: Colors.black87,
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.videocam_off_rounded, color: ObsidianUITheme.warningOrange, size: 36),
                                      const SizedBox(height: 8),
                                      Text(
                                        _cameraErrorMessage ?? 'Camera preview unavailable',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
                                            onPressed: _initDesktopCamera,
                                            icon: const Icon(Icons.refresh_rounded, size: 14),
                                            label: const Text('Retry Camera', style: TextStyle(fontSize: 11)),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(backgroundColor: borderColor),
                                            onPressed: _pasteFromClipboard,
                                            icon: Icon(Icons.assignment_turned_in_rounded, size: 14, color: primaryTextColor),
                                            label: Text('Paste Clipboard', style: TextStyle(fontSize: 11, color: primaryTextColor)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                            ] else if (_isCheckingPermission)
                              const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent))
                            else if (!_hasCameraPermission)
                              _buildPermissionDeniedCard(borderColor, primaryTextColor)
                            else if (_isScanning)
                              MobileScanner(
                                controller: _scannerController,
                                errorBuilder: (context, error) {
                                  if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
                                    return _buildPermissionDeniedCard(borderColor, primaryTextColor);
                                  }
                                  return Container(
                                    color: Colors.black87,
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.videocam_off_rounded, color: ObsidianUITheme.warningOrange, size: 36),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Camera Error: ${error.errorCode.name}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
                                              onPressed: () async {
                                                await _checkAndRequestPermission(directRequest: true);
                                                if (_hasCameraPermission) {
                                                  try {
                                                    await _scannerController.stop();
                                                    await _scannerController.start();
                                                  } catch (_) {}
                                                }
                                              },
                                              icon: const Icon(Icons.refresh_rounded, size: 14),
                                              label: const Text('Retry Camera', style: TextStyle(fontSize: 11)),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(backgroundColor: borderColor),
                                              onPressed: _pasteFromClipboard,
                                              icon: Icon(Icons.assignment_turned_in_rounded, size: 14, color: primaryTextColor),
                                              label: Text('Paste Clipboard', style: TextStyle(fontSize: 11, color: primaryTextColor)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                onDetect: (capture) {
                                  final List<Barcode> barcodes = capture.barcodes;
                                  for (final barcode in barcodes) {
                                    if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
                                      _handleRawScan(barcode.rawValue!);
                                      break;
                                    }
                                  }
                                },
                              )
                            else
                              Container(
                                color: Colors.black87,
                                child: Center(
                                  child: Text('Scanner Paused', style: TextStyle(color: tertiaryTextColor)),
                                ),
                              ),
                            // Viewfinder Reticle Overlay
                            if (_hasCameraPermission || _isDesktopWindows)
                              Container(
                                width: 210,
                                height: 210,
                                decoration: BoxDecoration(
                                  border: Border.all(color: ObsidianUITheme.primaryAccent, width: 2.5),
                                  borderRadius: BorderRadius.circular(16.0),
                                ),
                                child: const Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 6.0),
                                    child: Text(
                                      'ALIGN QR CODE HERE',
                                      style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 10.0, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(Icons.flash_on_rounded, color: secondaryTextColor),
                          tooltip: 'Toggle Flashlight',
                          onPressed: _safeToggleTorch,
                        ),
                        IconButton(
                          icon: Icon(_isScanning ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: ObsidianUITheme.primaryAccent, size: 36),
                          tooltip: _isScanning ? 'Pause Scanner' : 'Resume Scanner',
                          onPressed: () => setState(() => _isScanning = !_isScanning),
                        ),
                        IconButton(
                          icon: Icon(Icons.cameraswitch_rounded, color: secondaryTextColor),
                          tooltip: 'Switch Camera (PC Webcam)',
                          onPressed: _safeSwitchCamera,
                        ),
                        IconButton(
                          icon: const Icon(Icons.assignment_turned_in_rounded, color: ObsidianUITheme.primaryAccent),
                          tooltip: 'Paste Clipboard Code',
                          onPressed: _pasteFromClipboard,
                        ),
                      ],
                    ),
                  ] else ...[
                    // Manual Code Entry
                    TextField(
                      controller: _manualInputController,
                      maxLines: 3,
                      style: TextStyle(color: primaryTextColor, fontSize: 13.0),
                      decoration: InputDecoration(
                        labelText: 'Paste OSC: payload or JSON data',
                        labelStyle: TextStyle(color: secondaryTextColor),
                        hintText: 'OSC:... or {"type":"match-scout",...}',
                        hintStyle: TextStyle(color: faintTextColor),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: borderColor)),
                        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ObsidianUITheme.primaryAccent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              if (_manualInputController.text.trim().isNotEmpty) {
                                _handleRawScan(_manualInputController.text.trim());
                                _manualInputController.clear();
                              }
                            },
                            icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white),
                            label: const Text('PROCESS DATA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: borderColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _pasteFromClipboard,
                          icon: Icon(Icons.assignment_turned_in_rounded, color: primaryTextColor),
                          label: Text('PASTE CLIPBOARD', style: TextStyle(color: primaryTextColor, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16.0),

            // Queue Header & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SCANNED QUEUE',
                  style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0),
                ),
                Row(
                  children: [
                    if (_queue.isNotEmpty)
                      TextButton.icon(
                        onPressed: _clearQueue,
                        icon: Icon(Icons.delete_outline_rounded, size: 16, color: tertiaryTextColor),
                        label: Text('Clear', style: TextStyle(color: tertiaryTextColor, fontSize: 12)),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8.0),

            // Upload Queue Button
            ObsidianGlassCard(
              onTap: _isUploading || pendingCount == 0 ? null : _uploadQueue,
              child: Center(
                child: _isUploading
                    ? const CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_upload_rounded, color: primaryTextColor),
                          const SizedBox(width: 10.0),
                          Text(
                            pendingCount > 0 ? 'UPLOAD QUEUE ($pendingCount PENDING)' : 'QUEUE UPTODATE',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.0, color: primaryTextColor),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12.0),

            // Scanned Queue List
            if (_queue.isEmpty)
              ObsidianGlassCard(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text('No scanned items in queue. Point camera at barcode.', style: TextStyle(color: tertiaryTextColor)),
                  ),
                ),
              )
            else
              ..._queue.reversed.map((item) {
                final typeLabel = _getFormTypeLabel(item.type);
                final team = item.data['targetTeamNumber'] ?? 'Unknown';
                final match = item.data['matchKey']?.toString().split('_').last.toUpperCase() ?? (item.data['matchNumber'] != null ? 'M${item.data['matchNumber']}' : '');

                Color badgeColor = ObsidianUITheme.warningOrange;
                if (item.status == 'success') badgeColor = ObsidianUITheme.successGreen;
                if (item.status == 'error') badgeColor = ObsidianUITheme.errorRed;

                return ObsidianGlassCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$typeLabel - Team $team',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 14.0),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8.0),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4.0),
                                    border: Border.all(color: badgeColor),
                                  ),
                                  child: Text(
                                    item.status.toUpperCase(),
                                    style: TextStyle(color: badgeColor, fontSize: 10.0, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              'Event: ${item.data['eventKey'] ?? 'N/A'}${match.isNotEmpty ? " | Match: $match" : ""}',
                              style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
                            ),
                            if (item.errorMsg.isNotEmpty)
                              Text('Error: ${item.errorMsg}', style: const TextStyle(fontSize: 11.0, color: ObsidianUITheme.errorRed)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: tertiaryTextColor, size: 18),
                        onPressed: () => _removeQueueItem(item.id),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
