import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/bluetooth/ble_send_server.dart';
import '../services/bluetooth/ble_transfer_protocol.dart';
import '../theme/obsidian_ui_theme.dart';
import 'bluetooth_send_sheet.dart';
import 'obsidian_barcode_modal.dart';
import 'obsidian_glass_card.dart';

/// Shows a scouting entry as a QR code, or sends it over Bluetooth, from the same data.
void showEntryShare(
  BuildContext context, {
  required bool bluetooth,
  required Map<String, dynamic> payload,
  required String typeLabel,
  required int targetTeamNumber,
  String? teamLabel,
  String? matchKey,
  String? username,
}) {
  if (!bluetooth) {
    ObsidianBarcodeModal.show(
      context,
      payload: payload,
      typeLabel: typeLabel,
      targetTeamNumber: targetTeamNumber,
      teamLabel: teamLabel,
      matchKey: matchKey,
    );
    return;
  }
  if (!BleSendServer.platformSupported) {
    showBluetoothUnsupported(context);
    return;
  }
  final teams = ObsidianBarcodeModal.teamDisplay(payload, targetTeamNumber, teamLabel);
  final teamWord = teams.contains(',') ? 'Teams' : 'Team';
  final match = matchKey != null && matchKey.isNotEmpty ? ' - $matchKey' : '';
  final json = ObsidianBarcodeModal.envelopeJson(payload, typeLabel);
  BluetoothSendSheet.show(
    context,
    username: username,
    payload: BleTransferPayload(
      compressed: Uint8List.fromList(zlib.encode(utf8.encode(json))),
      summary: '$typeLabel - $teamWord $teams$match',
    ),
  );
}

/// Explains that Bluetooth needs the app on both devices (shown on the website instead of sending).
void showBluetoothUnsupported(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.bluetooth_disabled_rounded),
      title: Text(context.tr('bluetooth.send_title', 'Send over Bluetooth')),
      content: Text(context.tr('bluetooth.web_unsupported',
          'Bluetooth sending needs the ObsidianScout app on both devices. It is not available on the website.')),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(context.tr('qr.close', 'Close'))),
      ],
    ),
  );
}

/// The Send over Bluetooth button that sits beside a QR Code button. On the website it explains that Bluetooth
/// needs the app; on platforms with no Bluetooth support it is hidden.
class BluetoothSendCard extends StatelessWidget {
  final VoidCallback onTap;
  final bool compact;

  const BluetoothSendCard({super.key, required this.onTap, this.compact = false});

  static bool get visible => kIsWeb || BleSendServer.platformSupported;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return ObsidianGlassCard(
      key: const Key('bluetooth_send_button'),
      onTap: kIsWeb ? () => showBluetoothUnsupported(context) : onTap,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              kIsWeb ? Icons.bluetooth_disabled_rounded : Icons.bluetooth_rounded,
              color: ObsidianUITheme.primaryAccent,
              size: compact ? 20.0 : 24.0,
            ),
            SizedBox(width: compact ? 8.0 : 10.0),
            Flexible(
              child: Text(
                context.tr('bluetooth.send_title', 'Send over Bluetooth'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: compact ? 13.0 : 14.0,
                  color: ObsidianUITheme.getPrimaryTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
