import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/bluetooth/ble_transfer_protocol.dart';
import '../theme/obsidian_ui_theme.dart';

/// Lists devices trusted for Bluetooth transfer, each with a Forget button.
class TrustedDevicesDialog extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<BleTrustedPeer> peers;
  final Future<void> Function(BleTrustedPeer peer) onForget;

  const TrustedDevicesDialog({
    super.key,
    required this.title,
    required this.emptyText,
    required this.peers,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: peers.isEmpty
            ? Text(emptyText, style: TextStyle(color: secondaryText, fontSize: 13))
            : ListView.separated(
                shrinkWrap: true,
                itemCount: peers.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final peer = peers[i];
                  final label = peer.label.isEmpty
                      ? context.tr('bluetooth.unnamed_device', 'Unnamed device')
                      : peer.label;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      peer.role == BleTrustRole.scout ? Icons.smartphone_rounded : Icons.computer_rounded,
                      color: ObsidianUITheme.primaryAccent,
                    ),
                    title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      context.tr('bluetooth.trusted_since', 'Trusted {date}').replaceAll(
                          '{date}', MaterialLocalizations.of(context).formatMediumDate(peer.added.toLocal())),
                      style: TextStyle(fontSize: 12, color: secondaryText),
                    ),
                    trailing: TextButton(
                      onPressed: () => onForget(peer),
                      style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                      child: Text(context.tr('bluetooth.forget', 'Forget')),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('qr.close', 'Close'))),
      ],
    );
  }
}
