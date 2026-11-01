import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/net/net_client.dart';
import '../theme/obsidian_ui_theme.dart';

/// "Last updated 3:42 PM": when data last came from the server, an answer of "nothing changed" included. Screens
/// share one local copy of the data, so one time covers them all. Offline it says the data on show is the saved copy.
class LastUpdatedLine extends StatelessWidget {
  final ApiService apiService;

  const LastUpdatedLine({super.key, required this.apiService});

  static String formatTime(BuildContext context, DateTime at, {DateTime? now}) {
    final labels = MaterialLocalizations.of(context);
    final current = now ?? DateTime.now();
    final time = labels.formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final sameDay = at.year == current.year && at.month == current.month && at.day == current.day;
    return sameDay ? time : '${labels.formatShortMonthDay(at)} $time';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: apiService.onOnlineStatusChanged,
      initialData: apiService.isOnline,
      builder: (context, online) {
        return ValueListenableBuilder<DateTime?>(
          valueListenable: NetClient.lastDataAt,
          builder: (context, at, _) {
            final isOnline = online.data ?? true;
            final String text;
            if (at == null) {
              if (isOnline) return const SizedBox.shrink();
              text = context.tr('common.showing_saved_data', 'Showing saved data');
            } else {
              final prefix = isOnline
                  ? context.tr('common.last_updated', 'Last updated')
                  : context.tr('common.saved_data_from', 'Showing saved data from');
              text = '$prefix ${formatTime(context, at)}';
            }
            return Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context)),
            );
          },
        );
      },
    );
  }
}
