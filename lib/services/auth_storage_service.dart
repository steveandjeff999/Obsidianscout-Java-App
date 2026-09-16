import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredCredentials {
  final String username;
  final String password;
  final int teamNumber;
  final String program;
  final String serverUrl;
  final String jwt;

  StoredCredentials({
    required this.username,
    required this.password,
    required this.teamNumber,
    required this.program,
    required this.serverUrl,
    required this.jwt,
  });
}

class AuthStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyUsername = 'auth_username';
  static const String _keyPassword = 'auth_password';
  static const String _keyTeamNumber = 'auth_team_number';
  static const String _keyProgram = 'auth_program';
  static const String _keyServerUrl = 'auth_server_url';
  static const String _keyJwt = 'auth_jwt';
  static const String _keyEnrolled = 'auth_enrolled';
  static const String _keyRequireOnLaunch = 'auth_require_on_launch';
  static const String _keyBiometricPromptDismissed = 'auth_biometric_prompt_dismissed';

  /// Saves complete credentials after successful login.
  static Future<void> saveCredentials({
    required String username,
    required String password,
    required int teamNumber,
    required String program,
    required String serverUrl,
    required String jwt,
  }) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyTeamNumber, value: teamNumber.toString());
    await _storage.write(key: _keyProgram, value: program);
    await _storage.write(key: _keyServerUrl, value: serverUrl);
    await _storage.write(key: _keyJwt, value: jwt);
  }

  /// Loads stored credentials, or null if any critical fields are missing.
  static Future<StoredCredentials?> loadCredentials() async {
    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);
    final teamStr = await _storage.read(key: _keyTeamNumber);
    final program = await _storage.read(key: _keyProgram);
    final serverUrl = await _storage.read(key: _keyServerUrl);
    final jwt = await _storage.read(key: _keyJwt);

    if (username == null ||
        password == null ||
        teamStr == null ||
        program == null ||
        serverUrl == null) {
      return null;
    }

    final teamNumber = int.tryParse(teamStr) ?? 0;
    return StoredCredentials(
      username: username,
      password: password,
      teamNumber: teamNumber,
      program: program,
      serverUrl: serverUrl,
      jwt: jwt ?? '',
    );
  }

  /// Updates just the JWT token (e.g. after re-auth).
  static Future<void> updateJwt(String newJwt) async {
    await _storage.write(key: _keyJwt, value: newJwt);
  }

  /// Clears active session data on manual logout.
  /// If biometric sign-in is enrolled, securely preserved credentials remain
  /// so the user can easily log back in with Passkey / Biometrics.
  /// If biometric sign-in is NOT enrolled, all credentials are removed.
  static Future<void> clearCredentials() async {
    final enrolled = await isEnrolled();
    await _storage.delete(key: _keyJwt);
    await _storage.delete(key: _keyRequireOnLaunch);

    if (!enrolled) {
      await _storage.delete(key: _keyUsername);
      await _storage.delete(key: _keyPassword);
      await _storage.delete(key: _keyTeamNumber);
      await _storage.delete(key: _keyProgram);
      await _storage.delete(key: _keyServerUrl);
      await _storage.delete(key: _keyEnrolled);
    }
  }

  /// Completely purges all stored credentials and biometric enrollment data.
  static Future<void> purgeAll() async {
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keyTeamNumber);
    await _storage.delete(key: _keyProgram);
    await _storage.delete(key: _keyServerUrl);
    await _storage.delete(key: _keyJwt);
    await _storage.delete(key: _keyEnrolled);
    await _storage.delete(key: _keyRequireOnLaunch);
  }

  /// Whether biometric sign-in is enrolled.
  static Future<bool> isEnrolled() async {
    final val = await _storage.read(key: _keyEnrolled);
    return val == 'true';
  }

  /// Sets whether biometric sign-in is enrolled.
  static Future<void> setEnrolled(bool enrolled) async {
    await _storage.write(key: _keyEnrolled, value: enrolled ? 'true' : 'false');
    if (enrolled) {
      await setPromptDismissed(true);
    } else {
      // If disabled, also turn off require on launch and purge stored credentials
      await setRequireOnLaunch(false);
      await _storage.delete(key: _keyUsername);
      await _storage.delete(key: _keyPassword);
      await _storage.delete(key: _keyTeamNumber);
      await _storage.delete(key: _keyProgram);
      await _storage.delete(key: _keyServerUrl);
      await _storage.delete(key: _keyJwt);
    }
  }

  /// Whether biometric/passkey is mandatory on app launch.
  static Future<bool> isRequireOnLaunch() async {
    final val = await _storage.read(key: _keyRequireOnLaunch);
    return val == 'true';
  }

  /// Sets whether biometric/passkey is required on launch.
  static Future<void> setRequireOnLaunch(bool require) async {
    await _storage.write(key: _keyRequireOnLaunch, value: require ? 'true' : 'false');
  }

  /// Whether the user previously dismissed the biometric enrollment prompt.
  static Future<bool> isPromptDismissed() async {
    final val = await _storage.read(key: _keyBiometricPromptDismissed);
    return val == 'true';
  }

  /// Sets whether the biometric prompt has been dismissed.
  static Future<void> setPromptDismissed(bool dismissed) async {
    await _storage.write(key: _keyBiometricPromptDismissed, value: dismissed ? 'true' : 'false');
  }
}
