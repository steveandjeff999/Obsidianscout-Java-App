import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianBannerWidget extends StatefulWidget {
  final ApiService apiService;
  final bool isBarsVisible;

  const ObsidianBannerWidget({
    super.key,
    required this.apiService,
    this.isBarsVisible = true,
  });

  @override
  State<ObsidianBannerWidget> createState() => _ObsidianBannerWidgetState();
}

class _ObsidianBannerWidgetState extends State<ObsidianBannerWidget> {
  List<Map<String, dynamic>> _banners = [];
  final Set<String> _dismissedIds = {};
  bool _isLoading = true;
  StreamSubscription<bool>? _onlineSub;

  @override
  void initState() {
    super.initState();
    _loadBanners();
    _onlineSub = widget.apiService.onOnlineStatusChanged.listen((_) {
      if (mounted) {
        _loadBanners();
      }
    });
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    super.dispose();
  }

  Future<void> _loadBanners() async {
    final banners = await widget.apiService.fetchBanners();

    // Offline / local fallback check for missing eventKey or missing API key
    if (banners.isEmpty && !widget.apiService.isOnline) {
      final eventKey = await widget.apiService.fetchCurrentEventKey();
      if (eventKey == null || eventKey.isEmpty) {
        banners.add({
          'id': 'sys-no-event-key-offline',
          'message': 'No Event Key configured. Please set an Event Key in Settings.',
          'bannerType': 'warning',
          'isDismissible': true,
        });
      }
    }

    if (mounted) {
      setState(() {
        _banners = banners;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleBanners = _banners.where((b) => !_dismissedIds.contains(b['id'])).toList();

    if (_isLoading || visibleBanners.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: EdgeInsets.fromLTRB(
        16.0,
        widget.isBarsVisible ? 95.0 : 16.0,
        16.0,
        4.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: visibleBanners.map((banner) {
          final bannerType = (banner['bannerType'] ?? 'info').toString();
          final isDismissible = banner['isDismissible'] == true;
          final id = banner['id']?.toString() ?? '';

          Color bannerColor;
          IconData bannerIcon;

          switch (bannerType) {
            case 'warning':
              bannerColor = Colors.amber;
              bannerIcon = Icons.warning_amber_rounded;
              break;
            case 'danger':
            case 'error':
              bannerColor = ObsidianUITheme.errorRed;
              bannerIcon = Icons.error_outline_rounded;
              break;
            case 'success':
              bannerColor = Colors.greenAccent;
              bannerIcon = Icons.check_circle_outline_rounded;
              break;
            case 'info':
            default:
              bannerColor = ObsidianUITheme.primaryAccent;
              bannerIcon = Icons.info_outline_rounded;
              break;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.0),
              color: bannerColor.withValues(alpha: 0.15),
              border: Border.all(color: bannerColor.withValues(alpha: 0.5), width: 1.2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
            child: Row(
              children: [
                Icon(bannerIcon, color: bannerColor, size: 22.0),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text(
                    banner['message']?.toString() ?? '',
                    style: TextStyle(
                      color: ObsidianUITheme.getPrimaryTextColor(context),
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isDismissible)
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: ObsidianUITheme.getSecondaryTextColor(context), size: 18.0),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _dismissedIds.add(id);
                      });
                    },
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
