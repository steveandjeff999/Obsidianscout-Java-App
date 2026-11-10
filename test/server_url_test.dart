import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/server_url.dart';

void main() {
  test('moves the retired kotlin.obsidianscout.com address to the new one', () {
    expect(migrateLegacyServerUrl('https://kotlin.obsidianscout.com'), 'https://obsidianscout.com');
    expect(migrateLegacyServerUrl('https://Kotlin.ObsidianScout.com/'), 'https://obsidianscout.com');
    expect(migrateLegacyServerUrl('kotlin.obsidianscout.com'), 'https://obsidianscout.com');
  });

  test('leaves other addresses alone', () {
    expect(migrateLegacyServerUrl('https://obsidianscout.com'), 'https://obsidianscout.com');
    expect(migrateLegacyServerUrl('http://192.168.1.50:8080'), 'http://192.168.1.50:8080');
    expect(migrateLegacyServerUrl('https://scout.example.com'), 'https://scout.example.com');
    expect(migrateLegacyServerUrl(''), '');
  });
}
