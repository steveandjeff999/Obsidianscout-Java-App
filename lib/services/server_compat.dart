/// App <-> server compatibility, read from the server's `/api/version`.
///
/// Both sides carry an integer API level. Bump [kAppApiLevel] when this app starts relying on a server change
/// that older servers don't have, and raise [kMinServerApiLevel] to that server level. The server has the
/// matching pair (`ApiCompat` in the server's routes/Models.kt). A mismatch only shows a warning: the app keeps
/// working as far as the server allows.
library;

/// API level this build of the app speaks.
const int kAppApiLevel = 1;

/// Oldest server API level this app is built to work with. Servers from before the check report no level and
/// count as 0.
const int kMinServerApiLevel = 1;

/// Server API level that added the superadmin shared API keys (`/api/admin/shared-api-keys`). The app only shows
/// the editor on servers at this level or newer, since the feature is still being tested.
const int kSharedApiKeysServerApiLevel = 2;

enum ServerCompatStatus { compatible, serverTooOld, appTooOld }

class ServerCompatibility {
  final String serverVersion;
  final int serverApiLevel;
  final int minAppApiLevel;

  const ServerCompatibility({
    required this.serverVersion,
    required this.serverApiLevel,
    required this.minAppApiLevel,
  });

  factory ServerCompatibility.fromJson(Map<String, dynamic> json) => ServerCompatibility(
        serverVersion: json['version']?.toString() ?? 'unknown',
        serverApiLevel: (json['apiLevel'] as num?)?.toInt() ?? 0,
        minAppApiLevel: (json['minAppApiLevel'] as num?)?.toInt() ?? 0,
      );

  ServerCompatStatus get status {
    if (serverApiLevel < kMinServerApiLevel) return ServerCompatStatus.serverTooOld;
    if (kAppApiLevel < minAppApiLevel) return ServerCompatStatus.appTooOld;
    return ServerCompatStatus.compatible;
  }

  /// A banner in the shape the server's banners use, or null when the two sides are compatible. The id carries
  /// both levels, so a dismissed warning comes back if either side changes.
  Map<String, dynamic>? toBanner() {
    switch (status) {
      case ServerCompatStatus.compatible:
        return null;
      case ServerCompatStatus.serverTooOld:
        return {
          'id': 'sys-compat-server-old-$serverApiLevel-$kAppApiLevel',
          'bannerType': 'warning',
          'message': 'This server is older than this app expects. Some features may not work or may show errors '
              'until the server is updated.',
          'isDismissible': true,
          'isExpandable': true,
          'expandableMessage': 'Server version $serverVersion (API level $serverApiLevel). This app needs API level '
              '$kMinServerApiLevel or newer. Ask your server admin to update the server.',
        };
      case ServerCompatStatus.appTooOld:
        return {
          'id': 'sys-compat-app-old-$minAppApiLevel-$kAppApiLevel',
          'bannerType': 'warning',
          'message': 'This server is newer than this app. Some features may not work or may show errors until you '
              'update the app.',
          'isDismissible': true,
          'isExpandable': true,
          'expandableMessage': 'Server version $serverVersion needs app API level $minAppApiLevel or newer; this app '
              'is API level $kAppApiLevel. Update the app to the latest release.',
        };
    }
  }
}
