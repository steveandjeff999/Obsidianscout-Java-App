import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

/// Screen displayed when the application is locked via biometric / passkey launch lock.
class LaunchLockScreen extends StatelessWidget {
  final bool isUnlocking;
  final VoidCallback onUnlock;
  final VoidCallback onUsePassword;
  final VoidCallback onBackPress;

  const LaunchLockScreen({
    super.key,
    required this.isUnlocking,
    required this.onUnlock,
    required this.onUsePassword,
    required this.onBackPress,
  });

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        onBackPress();
      },
      child: Container(
        decoration: ObsidianUITheme.getBackgroundDecoration(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/obsidian-512.png',
                        width: 80.0,
                        height: 80.0,
                        cacheWidth: 160,
                        cacheHeight: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.shield_outlined,
                          size: 80.0,
                          color: ObsidianUITheme.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      Text(
                        context.tr('app.title'),
                        style: TextStyle(
                          fontSize: 32.0,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        'ObsidianScout is Locked',
                        style: TextStyle(
                          fontSize: 16.0,
                          fontWeight: FontWeight.w600,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 32.0),
                      ObsidianGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.fingerprint_rounded,
                                  size: 48.0,
                                  color: ObsidianUITheme.primaryAccent,
                                ),
                              ),
                              const SizedBox(height: 16.0),
                              Text(
                                'Passkey Authentication Required',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16.0,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              Text(
                                'Scan your biometric or passkey to unlock the application.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13.0,
                                  color: secondaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 24.0),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ObsidianUITheme.primaryAccent,
                                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                  ),
                                  onPressed: isUnlocking ? null : onUnlock,
                                  icon: isUnlocking
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.lock_open_rounded, color: Colors.white),
                                  label: Text(
                                    isUnlocking ? 'Unlocking...' : 'Unlock with Passkey',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15.0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12.0),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: ObsidianUITheme.getBorderColor(context)),
                                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                  ),
                                  onPressed: onUsePassword,
                                  icon: Icon(Icons.password_rounded, color: primaryTextColor),
                                  label: Text(
                                    'Use Password Instead',
                                    style: TextStyle(
                                      color: primaryTextColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
