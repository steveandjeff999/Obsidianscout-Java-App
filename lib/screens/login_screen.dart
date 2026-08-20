import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.apiService,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  late TextEditingController _serverUrlController;
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _teamNumberController = TextEditingController();

  // Register Controllers
  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regEmailController = TextEditingController();
  final TextEditingController _regTeamNumberController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regConfirmPasswordController = TextEditingController();

  String _selectedProgram = 'FRC';
  String _regProgram = 'FRC';
  String _regRole = 'SCOUT';
  bool _keepMeLoggedIn = true;
  bool _regKeepMeLoggedIn = true;

  bool _isSubmitting = false;
  bool _showServerConfig = false;
  int _activeTabIndex = 0; // 0 = Sign In, 1 = Create Account

  @override
  void initState() {
    super.initState();
    _serverUrlController = TextEditingController(text: widget.apiService.serverUrl);
    _keepMeLoggedIn = widget.apiService.keepMeLoggedIn;
    _regKeepMeLoggedIn = widget.apiService.keepMeLoggedIn;
    if (widget.apiService.savedUsername.isNotEmpty) {
      _usernameController.text = widget.apiService.savedUsername;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _teamNumberController.dispose();
    _regUsernameController.dispose();
    _regEmailController.dispose();
    _regTeamNumberController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    _loginFormKey.currentState!.save();

    setState(() => _isSubmitting = true);

    await widget.apiService.setServerUrl(_serverUrlController.text.trim());

    final success = await widget.apiService.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
      teamNumber: int.tryParse(_teamNumberController.text.trim()) ?? 0,
      program: _selectedProgram,
      keepMeLoggedIn: _keepMeLoggedIn,
    );

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (success) {
        widget.onLoginSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Login failed. Please check your credentials and server connection.'),
            backgroundColor: ObsidianUITheme.errorRed,
          ),
        );
      }
    }
  }

  void _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;
    _registerFormKey.currentState!.save();

    if (_regPasswordController.text != _regConfirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
          backgroundColor: ObsidianUITheme.warningOrange,
        ),
      );
      return;
    }

    final teamNum = int.tryParse(_regTeamNumberController.text.trim());
    if (teamNum == null || teamNum <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid positive team number'),
          backgroundColor: ObsidianUITheme.warningOrange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    await widget.apiService.setServerUrl(_serverUrlController.text.trim());

    final success = await widget.apiService.register(
      _regUsernameController.text.trim(),
      _regPasswordController.text,
      teamNumber: teamNum,
      program: _regProgram,
      email: _regEmailController.text.trim(),
      role: _regRole,
      keepMeLoggedIn: _regKeepMeLoggedIn,
    );

    setState(() => _isSubmitting = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('dashboard.sync_complete')),
            backgroundColor: ObsidianUITheme.successGreen,
          ),
        );
        widget.onLoginSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Registration failed. Please check your information and try again.'),
            backgroundColor: ObsidianUITheme.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    DropdownButton<String>(
                      value: widget.apiService.currentLocale.languageCode,
                      dropdownColor: surfaceColor,
                      style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                      underline: Container(height: 1, color: ObsidianUITheme.primaryAccent),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English 🇺🇸')),
                        DropdownMenuItem(value: 'es', child: Text('Español 🇪🇸')),
                        DropdownMenuItem(value: 'he', child: Text('עברית 🇮🇱')),
                        DropdownMenuItem(value: 'tr', child: Text('Türkçe 🇹🇷')),
                      ],
                      onChanged: (newLang) {
                        if (newLang != null) {
                          widget.apiService.setLocale(Locale(newLang));
                        }
                      },
                    ),
                  ],
                ),
                const Icon(
                  Icons.shield_outlined,
                  size: 64.0,
                  color: ObsidianUITheme.primaryAccent,
                ),
                const SizedBox(height: 12.0),
                Text(
                  context.tr('app.title'),
                  style: TextStyle(
                    fontSize: 32.0,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  context.tr('app.subtitle'),
                  style: TextStyle(fontSize: 14.0, color: secondaryTextColor),
                ),
                const SizedBox(height: 24.0),

                // Main Auth Glass Card
                ObsidianGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Server URL Configuration Header Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('login.server_config'),
                              style: const TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.bold,
                                color: ObsidianUITheme.primaryAccent,
                                letterSpacing: 1.0,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _showServerConfig ? Icons.settings : Icons.settings_outlined,
                              color: _showServerConfig ? ObsidianUITheme.primaryAccent : secondaryTextColor,
                              size: 20.0,
                            ),
                            onPressed: () {
                              setState(() => _showServerConfig = !_showServerConfig);
                            },
                          ),
                        ],
                      ),
                      if (_showServerConfig) ...[
                        const SizedBox(height: 8.0),
                        TextFormField(
                          controller: _serverUrlController,
                          style: TextStyle(color: primaryTextColor, fontSize: 14.0),
                          decoration: InputDecoration(
                            labelText: context.tr('login.server_url'),
                            labelStyle: TextStyle(color: secondaryTextColor),
                            hintText: 'http://localhost:8080 or https://192.168.1.100:8443',
                            hintStyle: TextStyle(color: faintTextColor),
                            prefixIcon: const Icon(Icons.dns_rounded, color: ObsidianUITheme.primaryAccent),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
                          ),
                        ),
                        const SizedBox(height: 12.0),
                      ],
                      Divider(color: borderColor),
                      const SizedBox(height: 12.0),

                      // Auth Tab Selector (Sign In vs Create Account)
                      Container(
                        decoration: BoxDecoration(
                          color: borderColor,
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(color: borderColor),
                        ),
                        padding: const EdgeInsets.all(4.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _activeTabIndex = 0),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                                  decoration: BoxDecoration(
                                    color: _activeTabIndex == 0 ? ObsidianUITheme.primaryAccent : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Text(
                                    context.tr('login.sign_in'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.0,
                                      color: _activeTabIndex == 0 ? Colors.white : secondaryTextColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _activeTabIndex = 1),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                                  decoration: BoxDecoration(
                                    color: _activeTabIndex == 1 ? ObsidianUITheme.secondaryAccent : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12.0),
                                  ),
                                  child: Text(
                                    context.tr('login.create_account'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.0,
                                      color: _activeTabIndex == 1 ? Colors.white : secondaryTextColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16.0),

                      // Render Login Form or Register Form
                      _activeTabIndex == 0 ? _buildLoginForm(primaryTextColor, secondaryTextColor, borderColor, surfaceColor) : _buildRegisterForm(primaryTextColor, secondaryTextColor, borderColor, surfaceColor),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),

                // Submit Button Card
                ObsidianGlassCard(
                  onTap: _isSubmitting ? null : (_activeTabIndex == 0 ? _handleLogin : _handleRegister),
                  child: Center(
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _activeTabIndex == 0 ? Icons.login_rounded : Icons.person_add_rounded,
                                color: primaryTextColor,
                              ),
                              const SizedBox(width: 10.0),
                              Text(
                                _activeTabIndex == 0 ? context.tr('login.connect_login') : context.tr('login.create_register'),
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0, color: primaryTextColor),
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
    );
  }

  Widget _buildLoginForm(Color primaryTextColor, Color secondaryTextColor, Color borderColor, Color surfaceColor) {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _usernameController,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.username'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.person_outline, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? context.tr('login.username') : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.password'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.lock_outline, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            validator: (val) => val == null || val.isEmpty ? context.tr('login.password') : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _teamNumberController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.team_number'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.group_outlined, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
          ),
          const SizedBox(height: 16.0),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedProgram,
            dropdownColor: surfaceColor,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.program'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.category_outlined, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            items: const [
              DropdownMenuItem(
                value: 'FRC',
                child: Text('FRC (FIRST Robotics Competition)', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(
                value: 'FTC',
                child: Text('FTC (FIRST Tech Challenge)', overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedProgram = val);
              }
            },
          ),
          const SizedBox(height: 12.0),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('login.keep_logged_in'), style: TextStyle(color: secondaryTextColor, fontSize: 14.0)),
              value: _keepMeLoggedIn,
              activeColor: ObsidianUITheme.primaryAccent,
              onChanged: (val) => setState(() => _keepMeLoggedIn = val ?? true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm(Color primaryTextColor, Color secondaryTextColor, Color borderColor, Color surfaceColor) {
    return Form(
      key: _registerFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _regUsernameController,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.new_username'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: const Icon(Icons.person_add_outlined, color: ObsidianUITheme.secondaryAccent),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? context.tr('login.username') : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _regEmailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.email_optional'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.email_outlined, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _regTeamNumberController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.team_number'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.group_outlined, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return context.tr('login.team_number');
              final n = int.tryParse(val.trim());
              if (n == null || n <= 0) return context.tr('login.team_number');
              return null;
            },
          ),
          const SizedBox(height: 16.0),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _regProgram,
            dropdownColor: surfaceColor,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.program'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.category_outlined, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            items: const [
              DropdownMenuItem(
                value: 'FRC',
                child: Text('FRC (FIRST Robotics Competition)', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(
                value: 'FTC',
                child: Text('FTC (FIRST Tech Challenge)', overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _regProgram = val);
              }
            },
          ),
          const SizedBox(height: 12.0),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _regRole,
            dropdownColor: surfaceColor,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.role'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: const Icon(Icons.badge_outlined, color: ObsidianUITheme.secondaryAccent),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            items: const [
              DropdownMenuItem(value: 'SCOUT', child: Text('Scout', overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'ANALYTICS', child: Text('Analytics', overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'ADMIN', child: Text('Admin', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _regRole = val);
              }
            },
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _regPasswordController,
            obscureText: true,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.password'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.lock_outline, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            validator: (val) => val == null || val.length < 4 ? context.tr('login.password') : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _regConfirmPasswordController,
            obscureText: true,
            style: TextStyle(color: primaryTextColor),
            decoration: InputDecoration(
              labelText: context.tr('login.confirm_password'),
              labelStyle: TextStyle(color: secondaryTextColor),
              prefixIcon: Icon(Icons.lock_reset_outlined, color: secondaryTextColor),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return context.tr('login.confirm_password');
              if (val != _regPasswordController.text) return context.tr('login.confirm_password');
              return null;
            },
          ),
          const SizedBox(height: 12.0),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('login.keep_logged_in'), style: TextStyle(color: secondaryTextColor, fontSize: 14.0)),
              value: _regKeepMeLoggedIn,
              activeColor: ObsidianUITheme.secondaryAccent,
              onChanged: (val) => setState(() => _regKeepMeLoggedIn = val ?? true),
            ),
          ),
        ],
      ),
    );
  }
}
