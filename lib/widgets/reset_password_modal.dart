import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../services/api_service.dart';

class ResetPasswordModal extends StatefulWidget {
  final ApiService apiService;
  final String? initialToken;
  final Function(String updatedUsername)? onResetSuccess;

  const ResetPasswordModal({
    super.key,
    required this.apiService,
    this.initialToken,
    this.onResetSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required ApiService apiService,
    String? initialToken,
    Function(String updatedUsername)? onResetSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ResetPasswordModal(
        apiService: apiService,
        initialToken: initialToken,
        onResetSuccess: onResetSuccess,
      ),
    );
  }

  @override
  State<ResetPasswordModal> createState() => _ResetPasswordModalState();
}

class _ResetPasswordModalState extends State<ResetPasswordModal> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _tokenController;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isVerifying = false;
  bool _isResetting = false;
  bool _tokenVerified = false;
  String? _tokenError;

  List<Map<String, dynamic>> _accounts = [];
  String? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken ?? '');
    if (_tokenController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _verifyToken();
        }
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _usernameController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _tokenError = 'Please enter a reset token';
        _tokenVerified = false;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _tokenError = null;
      _tokenVerified = false;
    });

    final response = await widget.apiService.verifyResetToken(token);

    if (!mounted) return;

    setState(() => _isVerifying = false);

    if (response.success && response.data != null) {
      final data = response.data!;
      final isValid = data['valid'] == true;
      final rawAccounts = data['accounts'];

      if (isValid && rawAccounts is List && rawAccounts.isNotEmpty) {
        final accounts = rawAccounts.map((item) {
          if (item is Map<String, dynamic>) return item;
          if (item is Map) return item.cast<String, dynamic>();
          return <String, dynamic>{};
        }).toList();

        setState(() {
          _tokenVerified = true;
          _accounts = accounts;
          _selectedUserId = accounts.first['userId']?.toString();
          _usernameController.text = accounts.first['username']?.toString() ?? '';
          _tokenError = null;
        });
      } else {
        setState(() {
          _tokenVerified = false;
          _tokenError = context.tr(
            'reset-password.this_password_reset_link_is_in',
            'This password reset token is invalid or has expired. Please request a new one.',
          );
        });
      }
    } else {
      setState(() {
        _tokenVerified = false;
        _tokenError = response.message ??
            context.tr(
              'reset-password.link_expired_or_invalid',
              'Link Expired or Invalid',
            );
      });
    }
  }

  Future<void> _handleReset() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    final token = _tokenController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final newUsername = _usernameController.text.trim();

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: ObsidianUITheme.warningOrange,
        ),
      );
      return;
    }

    setState(() => _isResetting = true);

    final response = await widget.apiService.resetPassword(
      token: token,
      userId: _selectedUserId,
      newUsername: newUsername.isNotEmpty ? newUsername : null,
      newPassword: newPassword,
    );

    if (!mounted) return;

    setState(() => _isResetting = false);

    if (response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message ?? 'Credentials have been reset successfully!',
          ),
          backgroundColor: ObsidianUITheme.successGreen,
        ),
      );
      if (widget.onResetSuccess != null) {
        widget.onResetSuccess!(newUsername);
      }
      Navigator.of(context, rootNavigator: true).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message ?? 'Failed to reset credentials'),
          backgroundColor: ObsidianUITheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ObsidianGlassCard(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_reset_rounded,
                            color: ObsidianUITheme.primaryAccent,
                            size: 24.0,
                          ),
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: Text(
                              _tokenVerified
                                  ? context.tr('reset-password.reset_credentials', 'Reset Credentials')
                                  : context.tr('reset_password.verify_reset_token', 'Enter Reset Token'),
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: secondaryTextColor, size: 20.0),
                      onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    ),
                  ],
                ),
                Text(
                  _tokenVerified
                      ? context.tr(
                          'reset-password.enter_your_new_password_below_',
                          'Enter your new credentials below.',
                        )
                      : 'Enter the reset token sent to your email to verify your account.',
                  style: TextStyle(fontSize: 13.0, color: secondaryTextColor),
                ),
                const SizedBox(height: 16.0),
                Divider(color: borderColor),
                const SizedBox(height: 12.0),

                // Token Input & Verify Button
                TextFormField(
                  controller: _tokenController,
                  style: TextStyle(color: primaryTextColor, fontSize: 14.0, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: 'Reset Token / Code',
                    labelStyle: TextStyle(color: secondaryTextColor),
                    hintText: 'Paste token from your email',
                    hintStyle: TextStyle(color: faintTextColor),
                    prefixIcon: const Icon(Icons.vpn_key_outlined, color: ObsidianUITheme.primaryAccent),
                    suffixIcon: _isVerifying
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: ObsidianUITheme.primaryAccent),
                            tooltip: 'Verify Token',
                            onPressed: _verifyToken,
                          ),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                  ),
                  onFieldSubmitted: (_) => _verifyToken(),
                ),
                if (!_tokenVerified) ...[
                  const SizedBox(height: 12.0),
                  TextButton.icon(
                    onPressed: _isVerifying ? null : _verifyToken,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      _isVerifying
                          ? context.tr('reset-password.verifying_your_reset_token', 'Verifying your reset token...')
                          : 'Verify Token',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: ObsidianUITheme.primaryAccent,
                    ),
                  ),
                ],

                if (_tokenError != null) ...[
                  const SizedBox(height: 12.0),
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.errorRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: ObsidianUITheme.errorRed.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, color: ObsidianUITheme.errorRed, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _tokenError!,
                            style: const TextStyle(color: ObsidianUITheme.errorRed, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Verified State: Show Account Selection & New Credentials Form
                if (_tokenVerified) ...[
                  const SizedBox(height: 16.0),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_accounts.length > 1) ...[
                          DropdownButtonFormField<String>(
                            value: _selectedUserId,
                            dropdownColor: surfaceColor,
                            style: TextStyle(color: primaryTextColor),
                            decoration: InputDecoration(
                              labelText: context.tr('reset-password.select_account_to_reset', 'Select Account to Reset'),
                              labelStyle: TextStyle(color: secondaryTextColor),
                              prefixIcon: Icon(Icons.switch_account_outlined, color: secondaryTextColor),
                              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                            ),
                            items: _accounts.map((acc) {
                              final uid = acc['userId']?.toString() ?? '';
                              final uname = acc['username']?.toString() ?? 'User';
                              final team = acc['teamNumber']?.toString() ?? '0';
                              return DropdownMenuItem(
                                value: uid,
                                child: Text('$uname (Team $team)', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedUserId = val;
                                  final matched = _accounts.firstWhere(
                                    (a) => a['userId']?.toString() == val,
                                    orElse: () => <String, dynamic>{},
                                  );
                                  if (matched.isNotEmpty) {
                                    _usernameController.text = matched['username']?.toString() ?? '';
                                  }
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12.0),
                        ],
                        TextFormField(
                          controller: _usernameController,
                          style: TextStyle(color: primaryTextColor),
                          decoration: InputDecoration(
                            labelText: context.tr('index.username', 'Username'),
                            labelStyle: TextStyle(color: secondaryTextColor),
                            prefixIcon: Icon(Icons.person_outline, color: secondaryTextColor),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty ? 'Username is required' : null,
                        ),
                        const SizedBox(height: 12.0),
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: true,
                          style: TextStyle(color: primaryTextColor),
                          decoration: InputDecoration(
                            labelText: context.tr('reset-password.new_password', 'New Password'),
                            labelStyle: TextStyle(color: secondaryTextColor),
                            prefixIcon: Icon(Icons.lock_outline, color: secondaryTextColor),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                          ),
                          validator: (val) => val == null || val.length < 4 ? 'Password must be at least 4 characters' : null,
                        ),
                        const SizedBox(height: 12.0),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          style: TextStyle(color: primaryTextColor),
                          decoration: InputDecoration(
                            labelText: context.tr('index.confirm_password', 'Confirm Password'),
                            labelStyle: TextStyle(color: secondaryTextColor),
                            prefixIcon: Icon(Icons.lock_reset_outlined, color: secondaryTextColor),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Please confirm password';
                            if (val != _newPasswordController.text) return 'Passwords do not match';
                            return null;
                          },
                        ),
                        const SizedBox(height: 20.0),
                        ElevatedButton(
                          onPressed: _isResetting ? null : _handleReset,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ObsidianUITheme.primaryAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                          ),
                          child: _isResetting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  context.tr('reset-password.reset_credentials_1', 'Reset credentials'),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
