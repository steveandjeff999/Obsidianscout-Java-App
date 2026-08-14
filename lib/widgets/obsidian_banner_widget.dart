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
  final Set<String> _expandedIds = {};
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: visibleBanners.map((banner) {
          final bannerType = (banner['bannerType'] ?? 'info').toString();
          final isDismissible = banner['isDismissible'] == true;
          final expandableMsg = banner['expandableMessage']?.toString().trim() ?? '';
          final isExpandable = banner['isExpandable'] == true && expandableMsg.isNotEmpty;
          final id = banner['id']?.toString() ?? '';
          final isExpanded = _expandedIds.contains(id);

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Icon(bannerIcon, color: bannerColor, size: 22.0),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        banner['message']?.toString() ?? '',
                        style: TextStyle(
                          color: ObsidianUITheme.getPrimaryTextColor(context),
                          fontSize: 13.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isExpandable) ...[
                        const SizedBox(height: 6.0),
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (isExpanded) {
                                _expandedIds.remove(id);
                              } else {
                                _expandedIds.add(id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(4.0),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isExpanded ? 'Show Less' : 'Read More',
                                  style: TextStyle(
                                    color: bannerColor,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 2.0),
                                Icon(
                                  isExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: bannerColor,
                                  size: 16.0,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(top: 6.0),
                            padding: const EdgeInsets.all(10.0),
                            decoration: BoxDecoration(
                              color: bannerColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(
                                color: bannerColor.withValues(alpha: 0.25),
                                width: 1.0,
                              ),
                            ),
                            child: Text(
                              expandableMsg,
                              style: TextStyle(
                                color: ObsidianUITheme.getPrimaryTextColor(context),
                                fontSize: 12.0,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ],
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
