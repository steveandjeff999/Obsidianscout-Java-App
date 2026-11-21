import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/bluetooth/ble_receive_client.dart';
import '../services/bluetooth/ble_transfer_protocol.dart';
import '../theme/obsidian_tokens.dart';
import '../theme/obsidian_ui_theme.dart';
import 'trusted_devices_dialog.dart';

/// Receiver side: lists scout phones that are sending and pulls an entry from the one the user picks. Trusted
/// phones send without a code; others ask for the code that phone shows.
class BluetoothReceiveSheet extends StatefulWidget {
  final Future<BleTransferResult> Function(BleTransferPayload payload) onPayload;

  /// Signed-in username, shown to phones this receiver pairs with.
  final String? username;

  const BluetoothReceiveSheet({super.key, required this.onPayload, this.username});

  static Future<void> show(
    BuildContext context, {
    required Future<BleTransferResult> Function(BleTransferPayload payload) onPayload,
    String? username,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BluetoothReceiveSheet(onPayload: onPayload, username: username),
    );
  }

  @override
  State<BluetoothReceiveSheet> createState() => _BluetoothReceiveSheetState();
}

class _ReceiveNote {
  final bool success;
  final String text;
  const _ReceiveNote(this.success, this.text);
}

class _BluetoothReceiveSheetState extends State<BluetoothReceiveSheet> {
  late final BleReceiveClient _client = BleReceiveClient(username: widget.username);
  String? _problem;
  bool _checking = true;
  String? _activeTag;
  BleReceiveStage? _stage;
  _ReceiveNote? _note;
  int _receivedCount = 0;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _checking = true;
      _problem = null;
    });
    final problem = await BleReceiveClient.checkReady();
    if (!mounted) return;
    if (problem == null) {
      try {
        await _client.startScan();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _checking = false;
          _problem = context.tr('bluetooth.scan_failed', 'Could not search for phones.');
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _problem = problem;
    });
  }

  Future<void> _pick(BleNearbyScout scout) async {
    if (_activeTag != null) return;
    setState(() {
      _activeTag = scout.tag;
      _stage = BleReceiveStage.connecting;
      _note = null;
    });
    try {
      final outcome = await _client.receive(
        scout,
        askCode: () => _askCode(scout),
        importer: widget.onPayload,
        onStage: (s) {
          if (mounted) setState(() => _stage = s);
        },
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final result = outcome.result;
      final who = outcome.senderLabel ??
          context.tr('bluetooth.phone_id', 'Phone {tag}').replaceAll('{tag}', scout.tag);
      setState(() {
        if (result.ok) _receivedCount++;
        if (!result.ok) {
          _note = _ReceiveNote(false,
              result.message.isEmpty ? context.tr('bluetooth.import_failed', 'The entry could not be read.') : result.message);
        } else if (outcome.newlyTrusted) {
          _note = _ReceiveNote(true,
              context.tr('bluetooth.received_paired', 'Received from {name}. This phone is now trusted, so next time no code is needed.')
                  .replaceAll('{name}', who));
        } else {
          _note = _ReceiveNote(true,
              context.tr('bluetooth.received_from_name', 'Received from {name}. It is in the queue below.').replaceAll('{name}', who));
        }
      });
    } on BleReceiveException catch (e) {
      if (!mounted) return;
      if (e.failure != BleReceiveFailure.cancelled) setState(() => _note = _ReceiveNote(false, e.message));
    } finally {
      if (mounted) {
        setState(() {
          _activeTag = null;
          _stage = null;
        });
      }
    }
  }

  Future<BleCodeAnswer?> _askCode(BleNearbyScout scout) {
    if (!mounted) return Future.value(null);
    return showDialog<BleCodeAnswer>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CodeDialog(tag: scout.tag),
    );
  }

  Future<void> _manageTrusted() {
    return showDialog<void>(
      context: context,
      builder: (_) => ValueListenableBuilder<List<BleTrustedPeer>>(
        valueListenable: _client.trustedScouts,
        builder: (ctx, peers, _) => TrustedDevicesDialog(
          title: context.tr('bluetooth.trusted_phones', 'Trusted phones'),
          emptyText: context.tr('bluetooth.no_trusted_phones',
              'No trusted phones yet. Tick "Trust this phone" when you enter a code to add one.'),
          peers: peers,
          onForget: (peer) => _client.forgetScout(peer.id),
        ),
      ),
    );
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
              Icon(Icons.bluetooth_searching_rounded, color: ObsidianUITheme.primaryAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('bluetooth.receive_title', 'Receive over Bluetooth'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryText),
                ),
              ),
              if (_receivedCount > 0)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Text(
                    context.tr('bluetooth.received_count', '{n} received').replaceAll('{n}', '$_receivedCount'),
                    style: const TextStyle(color: ObsidianUITheme.successGreen, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: secondaryText),
                tooltip: context.tr('qr.close', 'Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.tr('bluetooth.receive_instructions',
                  'On the scout\'s phone, open the entry\'s QR code and tap Send over Bluetooth. Then pick the phone here.'),
              style: TextStyle(color: secondaryText, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.install_mobile_rounded, size: 16, color: secondaryText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('bluetooth.app_only',
                      'Both devices need the ObsidianScout app. Bluetooth transfer is not available on the website.'),
                  style: TextStyle(color: secondaryText, fontSize: 12.5),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ValueListenableBuilder<List<BleTrustedPeer>>(
              valueListenable: _client.trustedScouts,
              builder: (context, peers, _) => TextButton.icon(
                key: const Key('bluetooth_manage_trusted'),
                onPressed: _manageTrusted,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: Text(context.tr('bluetooth.trusted_phones_count', 'Trusted phones ({n})')
                    .replaceAll('{n}', '${peers.length}')),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (_note != null) ...[
            _noteBanner(context, _note!),
            const SizedBox(height: 12),
          ],
          Flexible(child: _list(context)),
        ],
      ),
    );
  }

  Widget _noteBanner(BuildContext context, _ReceiveNote note) {
    final color = note.success ? ObsidianUITheme.successGreen : ObsidianUITheme.errorRed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(ObsidianTokens.radius),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(note.success ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(note.text, style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontSize: 13))),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    if (_checking) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_problem != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled_rounded, size: 40, color: ObsidianUITheme.warningOrange),
            const SizedBox(height: 10),
            Text(_problem!, textAlign: TextAlign.center, style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context))),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _begin,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('bluetooth.try_again', 'Try again')),
            ),
          ],
        ),
      );
    }
    return ValueListenableBuilder<List<BleNearbyScout>>(
      valueListenable: _client.scouts,
      builder: (context, scouts, _) {
        if (scouts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
                ),
                const SizedBox(width: 10),
                Text(context.tr('bluetooth.searching', 'Looking for phones...'), style: TextStyle(color: secondaryText)),
              ],
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: scouts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _scoutTile(context, scouts[i]),
        );
      },
    );
  }

  Widget _scoutTile(BuildContext context, BleNearbyScout scout) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final isActive = _activeTag == scout.tag;
    final disabled = _activeTag != null && !isActive;
    final trusted = scout.trustedPeer;
    final subtitle = isActive ? _stageText(context, _stage, trusted != null) : _signalText(context, scout);

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(ObsidianTokens.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(ObsidianTokens.radius),
          onTap: disabled || isActive ? null : () => _pick(scout),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  trusted != null ? Icons.verified_user_rounded : Icons.smartphone_rounded,
                  color: trusted != null ? ObsidianUITheme.successGreen : ObsidianUITheme.primaryAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('bluetooth.phone_id', 'Phone {tag}').replaceAll('{tag}', scout.tag),
                        style: TextStyle(
                          fontFamily: ObsidianTokens.fontMono,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: primaryText,
                        ),
                      ),
                      if (trusted != null && trusted.label.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          trusted.label,
                          key: const Key('bluetooth_trusted_label'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: primaryText, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(color: secondaryText, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (isActive)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: secondaryText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _signalText(BuildContext context, BleNearbyScout scout) {
    final rssi = scout.rssi;
    final strength = rssi == null
        ? ''
        : rssi >= -60
            ? context.tr('bluetooth.signal_strong', 'Strong signal')
            : rssi >= -80
                ? context.tr('bluetooth.signal_ok', 'Good signal')
                : context.tr('bluetooth.signal_weak', 'Weak signal');
    final name = scout.trustedPeer == null ? scout.name : null;
    final parts = [
      if (name != null) name,
      if (scout.trustedPeer != null) context.tr('bluetooth.trusted_no_code', 'Trusted - no code needed'),
      if (strength.isNotEmpty) strength,
    ];
    return parts.join(' - ');
  }

  String _stageText(BuildContext context, BleReceiveStage? stage, bool trusted) {
    switch (stage) {
      case BleReceiveStage.connecting:
      case null:
        return context.tr('bluetooth.stage_connecting', 'Connecting...');
      case BleReceiveStage.verifying:
        return trusted
            ? context.tr('bluetooth.stage_verifying_trusted', 'Checking trust...')
            : context.tr('bluetooth.stage_verifying', 'Checking the code...');
      case BleReceiveStage.waitingForCode:
        return context.tr('bluetooth.stage_waiting_code', 'Waiting for the code...');
      case BleReceiveStage.receiving:
        return context.tr('bluetooth.stage_receiving', 'Receiving...');
      case BleReceiveStage.importing:
        return context.tr('bluetooth.stage_importing', 'Adding to the queue...');
    }
  }
}

/// Asks for the code a scout's phone shows. Owns its text controller so the controller lives as long as the
/// dialog, including its closing animation.
class _CodeDialog extends StatefulWidget {
  final String tag;
  const _CodeDialog({required this.tag});

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;
  bool _trust = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = BleTransferProtocol.normalizeCode(_controller.text);
    if (code == null) {
      setState(() => _error = context.tr('bluetooth.code_invalid', 'Enter the 6-digit code.'));
      return;
    }
    Navigator.of(context).pop((code: code, trust: _trust));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('bluetooth.enter_code_title', 'Code for phone {tag}').replaceAll('{tag}', widget.tag)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('bluetooth.enter_code_body', "Type the code shown on the scout's phone."),
            style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bluetooth_code_field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 7,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
            style: const TextStyle(fontFamily: ObsidianTokens.fontMono, fontSize: 24, letterSpacing: 4),
            decoration: InputDecoration(hintText: '000 000', errorText: _error, counterText: ''),
            onSubmitted: (_) => _submit(),
          ),
          CheckboxListTile(
            key: const Key('bluetooth_trust_checkbox'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _trust,
            onChanged: (v) => setState(() => _trust = v ?? false),
            title: Text(context.tr('bluetooth.trust_this_phone', 'Trust this phone'), style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              context.tr('bluetooth.trust_this_phone_detail', 'Next time it can send to this device without a code.'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('common.cancel', 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.tr('bluetooth.receive', 'Receive')),
        ),
      ],
    );
  }
}
