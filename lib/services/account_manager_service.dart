import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// An account this device has signed in to, shown in the account switcher.
class SavedAccount {
  final String username;
  final int teamNumber;
  final String program;
  final String serverUrl;
  final String? role;
  /// Only a URL or server path; inline base64 pictures are too large for secure storage.
  final String? profilePicture;
  /// Null when the account was signed in without "keep me logged in", or its session expired.
  final String? sessionCookie;
  final DateTime lastUsed;

  const SavedAccount({
    required this.username,
    required this.teamNumber,
    required this.program,
    required this.serverUrl,
    this.role,
    this.profilePicture,
    this.sessionCookie,
    required this.lastUsed,
  });

  String get id => '${serverUrl.toLowerCase()}|$teamNumber|${username.toLowerCase()}';

  String get serverHost => Uri.tryParse(serverUrl)?.host ?? serverUrl;

  /// Same person on the same server. A team number of 0 (not typed at sign-in) matches any team.
  bool isSameAccount({required String username, required int teamNumber, required String serverUrl}) {
    if (this.username.toLowerCase() != username.trim().toLowerCase()) return false;
    if (this.serverUrl.toLowerCase() != serverUrl.toLowerCase()) return false;
    return this.teamNumber <= 0 || teamNumber <= 0 || this.teamNumber == teamNumber;
  }

  SavedAccount copyWith({
    String? username,
    int? teamNumber,
    String? program,
    String? serverUrl,
    String? role,
    String? profilePicture,
    String? sessionCookie,
    bool clearSessionCookie = false,
    DateTime? lastUsed,
  }) {
    return SavedAccount(
      username: username ?? this.username,
      teamNumber: teamNumber ?? this.teamNumber,
      program: program ?? this.program,
      serverUrl: serverUrl ?? this.serverUrl,
      role: role ?? this.role,
      profilePicture: profilePicture ?? this.profilePicture,
      sessionCookie: clearSessionCookie ? null : (sessionCookie ?? this.sessionCookie),
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'teamNumber': teamNumber,
        'program': program,
        'serverUrl': serverUrl,
        'role': role,
        'profilePicture': profilePicture,
        'sessionCookie': sessionCookie,
        'lastUsed': lastUsed.millisecondsSinceEpoch,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) {
    return SavedAccount(
      username: json['username']?.toString() ?? '',
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      program: json['program']?.toString() ?? 'FRC',
      serverUrl: json['serverUrl']?.toString() ?? '',
      role: json['role']?.toString(),
      profilePicture: json['profilePicture']?.toString(),
      sessionCookie: json['sessionCookie']?.toString(),
      lastUsed: DateTime.fromMillisecondsSinceEpoch((json['lastUsed'] as num?)?.toInt() ?? 0),
    );
  }

  /// Keeps only picture references small enough to store (URLs and server paths).
  static String? storablePicture(String? picture) {
    final pic = picture?.trim();
    if (pic == null || pic.isEmpty || pic.length > 2048 || pic.startsWith('data:')) return null;
    return pic;
  }
}

/// Stores the list of signed-in accounts. Session cookies are kept in secure storage.
class AccountManagerService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyAccounts = 'auth_saved_accounts';
  static const int maxAccounts = 10;

  static Future<List<SavedAccount>> load() async {
    try {
      final raw = await _storage.read(key: _keyAccounts);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((m) => SavedAccount.fromJson(Map<String, dynamic>.from(m)))
          .where((a) => a.username.isNotEmpty && a.serverUrl.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<SavedAccount> accounts) async {
    final sorted = [...accounts]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    final trimmed = sorted.take(maxAccounts).toList();
    await _storage.write(key: _keyAccounts, value: jsonEncode(trimmed.map((a) => a.toJson()).toList()));
  }

  static Future<void> clear() async {
    await _storage.delete(key: _keyAccounts);
  }
}
