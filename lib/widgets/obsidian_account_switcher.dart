import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/account_manager_service.dart';
import '../services/api_service.dart';
import '../services/fcm_helper.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_user_avatar.dart';

enum AccountMenuActionType { switchTo, addAccount, signOut, signOutAll }

/// What the user picked in the account switcher; the shell carries it out.
class AccountMenuAction {
  final AccountMenuActionType type;
  final SavedAccount? account;

  const AccountMenuAction(this.type, [this.account]);
}

/// Opens the account switcher: the signed-in account, the other saved accounts,
/// "Add another account" and sign-out options. Removing a saved account happens in place.
Future<AccountMenuAction?> showObsidianAccountSwitcher({
  required BuildContext context,
  required ApiService apiService,
  bool alignLeft = false,
}) {
  return showDialog<AccountMenuAction>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => _AccountSwitcherDialog(apiService: apiService, alignLeft: alignLeft),
  );
}

class _AccountSwitcherDialog extends StatelessWidget {
  final ApiService apiService;
  final bool alignLeft;

  const _AccountSwitcherDialog({required this.apiService, required this.alignLeft});

  @override
  Widget build(BuildContext context) {
    final surface = ObsidianUITheme.getElevatedSurfaceColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final radius = ObsidianUITheme.getButtonRadius(context, fallback: 16.0).clamp(8.0, 24.0);

    return Dialog(
      alignment: alignLeft ? Alignment.topLeft : Alignment.topCenter,
      insetPadding: alignLeft
          ? const EdgeInsets.fromLTRB(12.0, 64.0, 16.0, 24.0)
          : const EdgeInsets.fromLTRB(16.0, 56.0, 16.0, 24.0),
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380.0),
        child: ValueListenableBuilder<List<SavedAccount>>(
          valueListenable: apiService.savedAccountsNotifier,
          builder: (context, _, __) => _buildContent(context, radius),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, double radius) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final accent = ObsidianUITheme.getPrimaryAccent(context);

    final user = apiService.currentUser;
    final active = apiService.activeSavedAccount;
    final username = user?.username.isNotEmpty == true
        ? user!.username
        : (active?.username ?? apiService.savedUsername);
    final team = (user?.teamNumber ?? 0) > 0 ? user!.teamNumber : (active?.teamNumber ?? 0);
    final program = user?.program ?? active?.program ?? apiService.currentProgram;
    final roleLabel = user?.roleDisplayLabel ?? 'Scout';
    final others = apiService.otherSavedAccounts;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Signed-in account
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 12.0, 8.0, 0.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    Uri.tryParse(apiService.currentServerUrl)?.host ?? apiService.currentServerUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.0, color: secondaryText, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 20.0, color: secondaryText),
                  tooltip: context.tr('accounts.close', 'Close'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 18.0),
            child: Column(
              children: [
                ObsidianUserAvatar(
                  profilePicture: user?.profilePicture ?? active?.profilePicture,
                  username: username,
                  size: 72,
                  serverUrl: apiService.currentServerUrl,
                ),
                const SizedBox(height: 12.0),
                Text(
                  context.tr('accounts.greeting', 'Hi, {name}!').replaceAll('{name}', username),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19.0, fontWeight: FontWeight.w600, color: primaryText),
                ),
                const SizedBox(height: 4.0),
                Text(
                  team > 0 ? '$program Team $team' : program,
                  style: TextStyle(fontSize: 13.0, color: secondaryText),
                ),
                const SizedBox(height: 8.0),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: accent.withValues(alpha: 0.4), width: 0.8),
                  ),
                  child: Text(
                    roleLabel,
                    style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w700, color: accent),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),

          // Other accounts
          for (final account in others)
            _OtherAccountRow(
              account: account,
              apiService: apiService,
              onTap: () => Navigator.of(context).pop(AccountMenuAction(AccountMenuActionType.switchTo, account)),
            ),

          _MenuRow(
            icon: Icons.person_add_alt_1_rounded,
            iconColor: accent,
            label: context.tr('accounts.add', 'Add another account'),
            onTap: () => Navigator.of(context).pop(const AccountMenuAction(AccountMenuActionType.addAccount)),
          ),
          Divider(height: 1, color: borderColor),
          _MenuRow(
            icon: Icons.logout_rounded,
            iconColor: secondaryText,
            label: context.tr('accounts.sign_out', 'Sign out'),
            onTap: () => Navigator.of(context).pop(const AccountMenuAction(AccountMenuActionType.signOut)),
          ),
          if (others.isNotEmpty)
            _MenuRow(
              icon: Icons.no_accounts_rounded,
              iconColor: ObsidianUITheme.errorRed,
              label: context.tr('accounts.sign_out_all', 'Sign out of all accounts'),
              onTap: () => Navigator.of(context).pop(const AccountMenuAction(AccountMenuActionType.signOutAll)),
            ),
          const SizedBox(height: 8.0),
        ],
      ),
    );
  }
}

class _OtherAccountRow extends StatelessWidget {
  final SavedAccount account;
  final ApiService apiService;
  final VoidCallback onTap;

  const _OtherAccountRow({required this.account, required this.apiService, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final signedIn = apiService.hasActiveSession(account);
    final details = [
      if (account.teamNumber > 0) '${account.program} Team ${account.teamNumber}' else account.program,
      if (account.serverUrl.toLowerCase() != apiService.currentServerUrl.toLowerCase()) account.serverHost,
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20.0, 10.0, 8.0, 10.0),
        child: Row(
          children: [
            Opacity(
              opacity: signedIn ? 1.0 : 0.6,
              child: ObsidianUserAvatar(
                profilePicture: account.profilePicture,
                username: account.username,
                size: 36,
                serverUrl: account.serverUrl,
              ),
            ),
            const SizedBox(width: 14.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.w600, color: primaryText),
                  ),
                  Text(
                    signedIn ? details : '$details · ${context.tr('accounts.signed_out', 'Signed out')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.0, color: secondaryText),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.remove_circle_outline_rounded, size: 20.0, color: secondaryText),
              tooltip: context.tr('accounts.remove', 'Remove account'),
              onPressed: () => apiService.removeSavedAccount(account, fcmToken: FcmHelper.currentFcmToken),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _MenuRow({required this.icon, required this.iconColor, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
        child: Row(
          children: [
            SizedBox(width: 36.0, child: Icon(icon, size: 22.0, color: iconColor)),
            const SizedBox(width: 14.0),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14.0,
                  fontWeight: FontWeight.w500,
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
