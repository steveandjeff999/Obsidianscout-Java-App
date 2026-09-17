import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/widgets/obsidian_banner_widget.dart';

class _MockBannerApiService extends ApiService {
  List<Map<String, dynamic>> mockBanners = [];
  int fetchCallCount = 0;
  final StreamController<bool> _onlineController = StreamController<bool>.broadcast();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onOnlineStatusChanged => _onlineController.stream;

  @override
  Future<List<Map<String, dynamic>>> fetchBanners() async {
    fetchCallCount++;
    return List<Map<String, dynamic>>.from(mockBanners);
  }

  void dispose() {
    _onlineController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ObsidianBannerWidget updates banners periodically every 10 seconds and eliminates stale banners', (tester) async {
    final mockApi = _MockBannerApiService();
    mockApi.mockBanners = [
      {
        'id': 'banner-1',
        'message': 'Initial Stale Banner',
        'bannerType': 'info',
        'isDismissible': false,
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ObsidianBannerWidget(apiService: mockApi),
        ),
      ),
    );

    // Initial load
    await tester.pump();
    expect(find.text('Initial Stale Banner'), findsOneWidget);
    expect(mockApi.fetchCallCount, 1);

    // Advance 5 seconds - should NOT have polled yet
    await tester.pump(const Duration(seconds: 5));
    expect(mockApi.fetchCallCount, 1);
    expect(find.text('Initial Stale Banner'), findsOneWidget);

    // Update the server banners (simulate stale banner removed, new banner added)
    mockApi.mockBanners = [
      {
        'id': 'banner-2',
        'message': 'Fresh Updated Banner',
        'bannerType': 'warning',
        'isDismissible': false,
      },
    ];

    // Advance another 5 seconds (total 10 seconds elapsed)
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(mockApi.fetchCallCount, 2);
    // The stale banner should be gone!
    expect(find.text('Initial Stale Banner'), findsNothing);
    // The new banner should be displayed!
    expect(find.text('Fresh Updated Banner'), findsOneWidget);

    // Advance another 10 seconds with empty banners (simulate banner deleted / expired)
    mockApi.mockBanners = [];
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(mockApi.fetchCallCount, 3);
    expect(find.text('Fresh Updated Banner'), findsNothing);

    // Cleanup widget tree to trigger dispose
    await tester.pumpWidget(const SizedBox.shrink());
    mockApi.dispose();
  });
}
