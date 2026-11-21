import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/bluetooth/ble_send_server.dart';
import '../services/bluetooth/ble_transfer_protocol.dart';
import '../theme/obsidian_tokens.dart';
import '../theme/obsidian_ui_theme.dart';
import 'trusted_devices_dialog.dart';

/// Scout side: advertises this entry and shows the one-time code a new receiver must type. Trusted receivers
/// connect without it.
class BluetoothSendSheet extends StatefulWidget {
  final BleTransferPayload payload;

  /// Signed-in username, shown to receivers this phone pairs with.
  final String? username;

  const BluetoothSendSheet({super.key, required this.payload, this.username});

  static Future<void> show(BuildContext context, {required BleTransferPayload payload, String? username}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BluetoothSendSheet(payload: payload, username: username),
    );
  }

  @override
  State<BluetoothSendSheet> createState() => _BluetoothSendSheetState();
}

class _BluetoothSendSheetState extends State<BluetoothSendSheet> {
  late final BleSendServer _server = BleSendServer(payload: widget.payload, username: widget.username);

  /// Whether the screen was already being kept on (e.g. the keep-screen-on-while-scouting setting) before
  /// this sheet opened. Resolves after this sheet has turned the wakelock on.
  late final Future<bool> _wakelockWasOn;

  @override
  void initState() {
    super.initState();
    _server.addListener(_onChange);
    // Advertising stops when the screen locks on iOS, so keep it on while the code is up.
    _wakelockWasOn = _holdWakelock();
    _server.start();
  }

  static Future<bool> _holdWakelock() async {
    var wasOn = false;
    try {
      wasOn = await WakelockPlus.enabled;
    } catch (_) {}
    if (!wasOn) await WakelockPlus.enable().catchError((_) {});
    return wasOn;
  }

  @override
  void dispose() {
    _server.removeListener(_onChange);
    _server.dispose();
    // Only release the wakelock if this sheet took it, so the scouting screen's own setting stays in effect.
    _wakelockWasOn.then((wasOn) {
      if (!wasOn) return WakelockPlus.disable().catchError((_) {});
    });
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final surface = ObsidianUITheme.getSurfaceColor(context);
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewPadding.bottom + 20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(ObsidianTokens.radius)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: ObsidianUITheme.getFaintTextColor(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.bluetooth_rounded, color: ObsidianUITheme.primaryAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('bluetooth.send_title', 'Send over Bluetooth'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryText),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: secondaryText),
                tooltip: context.tr('qr.close', 'Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (widget.payload.summary.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(widget.payload.summary, style: TextStyle(color: secondaryText, fontSize: 13)),
            ),
          const SizedBox(height: 16),
          Flexible(child: SingleChildScrollView(child: _body(context))),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (_server.state) {
      case BleSendState.idle:
      case BleSendState.starting:
        return _status(
          context,
          icon: null,
          title: context.tr('bluetooth.starting', 'Starting Bluetooth...'),
        );
      case BleSendState.waiting:
        return _waiting(context);
      case BleSendState.transferring:
        return _status(
          context,
          icon: null,
          title: context.tr('bluetooth.sending', 'Receiver connected. Sending...'),
          detail: context.tr('bluetooth.keep_open', 'Keep this screen open until the transfer finishes.'),
        );
      case BleSendState.delivered:
        final who = _server.receiverName;
        return _status(
          context,
          icon: Icons.check_circle_rounded,
          color: ObsidianUITheme.successGreen,
          title: who == null
              ? context.tr('bluetooth.delivered', 'Entry received')
              : context.tr('bluetooth.delivered_by', 'Entry received by {name}').replaceAll('{name}', who),
          detail: _server.newlyTrusted
              ? context.tr('bluetooth.now_trusted', 'This receiver is now trusted. Next time it can receive from this phone without a code.')
              : _server.deliveredViaTrust
                  ? context.tr('bluetooth.sent_trusted', 'Sent to a trusted receiver, no code needed.')
                  : null,
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('bluetooth.done', 'Done')),
          ),
        );
      case BleSendState.locked:
        return _status(
          context,
          icon: Icons.lock_rounded,
          color: ObsidianUITheme.errorRed,
          title: context.tr('bluetooth.locked', 'Too many wrong codes'),
          detail: context.tr('bluetooth.locked_detail',
              'Sending stopped so nobody can keep guessing. Start again when the receiver is ready.'),
          action: _restartButton(context),
        );
      case BleSendState.unavailable:
      case BleSendState.error:
        return _status(
          context,
          icon: Icons.bluetooth_disabled_rounded,
          color: ObsidianUITheme.warningOrange,
          title: _server.message ?? context.tr('bluetooth.unavailable', 'Bluetooth is not available.'),
          action: _restartButton(context),
        );
    }
  }

  Widget _waiting(BuildContext context) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final code = _server.code;
    final spaced = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.tr('bluetooth.send_instructions_trusted',
                  'On the receiver, pick phone {tag}. Trusted receivers connect right away; others enter this code:')
              .replaceAll('{tag}', _server.tag),
          textAlign: TextAlign.center,
          style: TextStyle(color: secondaryText, fontSize: 14),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(ObsidianTokens.radius),
            border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Semantics(
                label: context.tr('bluetooth.code', 'Code'),
                child: Text(
                  spaced,
                  key: const Key('bluetooth_send_code'),
                  style: TextStyle(
                    fontFamily: ObsidianTokens.fontMono,
                    fontSize: 44,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4,
                    color: primaryText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('bluetooth.phone_id', 'Phone {tag}').replaceAll('{tag}', _server.tag),
                style: TextStyle(
                  fontFamily: ObsidianTokens.fontMono,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ObsidianUITheme.primaryAccent,
                ),
              ),
            ],
          ),
        ),
        if (_server.message != null && _server.failedAttempts > 0) ...[
          const SizedBox(height: 12),
          _notice(
            context,
            Icons.warning_amber_rounded,
            ObsidianUITheme.warningOrange,
            '${_server.message} ${context.tr('bluetooth.attempts_left', '{n} tries left.').replaceAll('{n}', '${BleTransferProtocol.maxFailedAttempts - _server.failedAttempts}')}',
          ),
        ] else if (_server.message != null) ...[
          const SizedBox(height: 12),
          _notice(context, Icons.info_outline_rounded, secondaryText, _server.message!),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                context.tr('bluetooth.waiting', 'Waiting for the receiver. Keep this screen open.'),
                style: TextStyle(color: secondaryText, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _notice(
          context,
          Icons.shield_outlined,
          secondaryText,
          context.tr('bluetooth.code_security',
              'The entry is encrypted with this code. Each code works once; a wrong guess replaces it.'),
        ),
        const SizedBox(height: 8),
        _notice(
          context,
          Icons.install_mobile_rounded,
          secondaryText,
          context.tr('bluetooth.app_only',
              'Both devices need the ObsidianScout app. Bluetooth transfer is not available on the website.'),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('bluetooth_manage_trusted'),
            onPressed: _manageTrusted,
            icon: const Icon(Icons.verified_user_outlined, size: 18),
            label: Text(context.tr('bluetooth.trusted_receivers_count', 'Trusted receivers ({n})')
                .replaceAll('{n}', '${_server.trustedReceivers.length}')),
          ),
        ),
      ],
    );
  }

  Future<void> _manageTrusted() {
    return showDialog<void>(
      context: context,
      builder: (_) => ListenableBuilder(
        listenable: _server,
        builder: (ctx, _) => TrustedDevicesDialog(
          title: context.tr('bluetooth.trusted_receivers', 'Trusted receivers'),
          emptyText: context.tr('bluetooth.no_trusted_receivers',
              "No trusted receivers yet. A receiver becomes trusted when it enters this phone's code with Trust this phone ticked."),
          peers: _server.trustedReceivers,
          onForget: (peer) => _server.forgetReceiver(peer.id),
        ),
      ),
    );
  }

  Widget _notice(BuildContext context, IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color))),
      ],
    );
  }

  Widget _status(
    BuildContext context, {
    required IconData? icon,
    required String title,
    Color? color,
    String? detail,
    Widget? action,
  }) {
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3, color: ObsidianUITheme.primaryAccent),
            )
          else
            Icon(icon, size: 44, color: color ?? ObsidianUITheme.primaryAccent),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: ObsidianUITheme.getPrimaryTextColor(context),
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(detail, textAlign: TextAlign.center, style: TextStyle(color: secondaryText, fontSize: 13)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }

  Widget _restartButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _server.restart,
      icon: const Icon(Icons.refresh_rounded),
      label: Text(context.tr('bluetooth.start_again', 'Start again')),
    );
  }
}
