import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Checks whether the device hardware supports biometrics / Windows Hello / device passcode,
  /// AND at least one biometric or credential is enrolled on the device.
  static Future<bool> isAvailable() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) return false;

      final canCheck = await _auth.canCheckBiometrics;
      final biometrics = await _auth.getAvailableBiometrics();
      return canCheck || biometrics.isNotEmpty;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns enrolled biometric types (e.g. fingerprint, face, iris).
  static Future<List<BiometricType>> getEnrolledBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Prompts the user with the OS biometric / Windows Hello / passcode dialog.
  /// Returns true on successful authentication, false on cancellation/failure.
  static Future<bool> authenticate({
    String reason = 'Authenticate to access ObsidianScout',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allows device PIN/passcode fallback if configured
        ),
      );
    } on PlatformException {
      // User cancelled or hardware locked/unavailable
      return false;
    } catch (_) {
      return false;
    }
  }
}
