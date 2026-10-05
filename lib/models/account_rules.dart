/// Account rules shared by every form that creates or edits a user.
///
/// These mirror the server (AuthService.validateUsername / validatePassword) so users get
/// immediate feedback instead of a rejected request. The server remains the authority.
class AccountRules {
  AccountRules._();

  static const int minPasswordLength = 8;
  static const int maxUsernameLength = 64;

  /// Self-registration roles, in the order the server and website use.
  static const List<String> selfRegisterRoles = ['ADMIN', 'ANALYTICS', 'SCOUT'];

  static const String _forbiddenUsernameChars = '/\\:*?"<>|`';

  /// Returns an error message, or null when [username] is acceptable.
  static String? validateUsername(String? username) {
    final trimmed = (username ?? '').trim();
    if (trimmed.isEmpty) return 'Username is required';
    if (trimmed.length > maxUsernameLength) {
      return 'Username must be at most $maxUsernameLength characters';
    }
    final hasForbidden = trimmed.contains('..') ||
        trimmed.runes.any((r) => r < 0x20 || r == 0x7F || _forbiddenUsernameChars.contains(String.fromCharCode(r)));
    if (hasForbidden) {
      return 'Username cannot contain ".." or any of: / \\ : * ? " < > | `';
    }
    return null;
  }

  /// Returns an error message, or null when [password] is acceptable.
  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) return 'Password is required';
    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters long';
    }
    return null;
  }
}
