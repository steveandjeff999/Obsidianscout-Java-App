/// The server address new installs start on.
const String defaultServerUrl = "https://obsidianscout.com";

/// The old default address, being retired. Saved URLs that point at it are moved to [defaultServerUrl].
const String _legacyServerHost = "kotlin.obsidianscout.com";

/// Returns [url] unchanged unless it points at the retired kotlin.obsidianscout.com address,
/// in which case it returns [defaultServerUrl]. Same server, so saved sessions keep working.
String migrateLegacyServerUrl(String url) {
  final trimmed = url.trim();
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final host = Uri.tryParse(withScheme)?.host.toLowerCase();
  return host == _legacyServerHost ? defaultServerUrl : url;
}
