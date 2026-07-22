import 'package:flutter/material.dart';
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
  final TextEditingController _usernameController = TextEditingController(text: 'admin');
  final TextEditingController _passwordController = TextEditingController(text: 'changeme');
  final TextEditingController _teamNumberController = TextEditingController(text: '0');

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
          const SnackBar(
            content: Text('Failed to authenticate. Check credentials & server URL.'),
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
          const SnackBar(
            content: Text('Account created successfully! Logged in.'),
            backgroundColor: ObsidianUITheme.successGreen,
          ),
        );
        widget.onLoginSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration failed. Check details or server connectivity.'),
            backgroundColor: ObsidianUITheme.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: ObsidianUITheme.background,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 64.0,
                  color: ObsidianUITheme.primaryAccent,
                ),
                const SizedBox(height: 12.0),
                const Text(
                  'Obsidianscout',
                  style: TextStyle(
                    fontSize: 32.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const Text(
                  'Scouting Portal Authentication',
                  style: TextStyle(fontSize: 14.0, color: Colors.white54),
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
                          const Expanded(
                            child: Text(
                              'SERVER CONFIGURATION',
                              style: TextStyle(
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
                              color: _showServerConfig ? ObsidianUITheme.primaryAccent : Colors.white60,
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
                          style: const TextStyle(color: Colors.white, fontSize: 14.0),
                          decoration: const InputDecoration(
                            labelText: 'Server Host / URL',
                            labelStyle: TextStyle(color: Colors.white60),
                            hintText: 'http://localhost:8080 or https://192.168.1.100:8443',
                            hintStyle: TextStyle(color: Colors.white24),
                            prefixIcon: Icon(Icons.dns_rounded, color: ObsidianUITheme.primaryAccent),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          ),
                        ),
                        const SizedBox(height: 12.0),
                      ],
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 12.0),

                      // Auth Tab Selector (Sign In vs Create Account)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(color: Colors.white12),
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
                                    'Sign In',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.0,
                                      color: _activeTabIndex == 0 ? Colors.white : Colors.white60,
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
                                    'Create Account',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.0,
                                      color: _activeTabIndex == 1 ? Colors.white : Colors.white60,
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
                      _activeTabIndex == 0 ? _buildLoginForm() : _buildRegisterForm(),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),

                // Submit Button Card
                ObsidianGlassCard(
                  onTap: _isSubmitting ? null : (_activeTabIndex == 0 ? _handleLogin : _handleRegister),
                  child: Center(
                    child: _isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _activeTabIndex == 0 ? Icons.login_rounded : Icons.person_add_rounded,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 10.0),
                              Text(
                                _activeTabIndex == 0 ? 'CONNECT & LOGIN' : 'CREATE ACCOUNT & REGISTER',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0, color: Colors.white),
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

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Username',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.person_outline, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Username required' : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Password',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.lock_outline, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            validator: (val) => val == null || val.isEmpty ? 'Password required' : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _teamNumberController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Team Number',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.group_outlined, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
          ),
          const SizedBox(height: 16.0),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedProgram,
            dropdownColor: ObsidianUITheme.surface,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Program',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.category_outlined, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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
              title: const Text('Keep Me Logged In', style: TextStyle(color: Colors.white70, fontSize: 14.0)),
              value: _keepMeLoggedIn,
              activeColor: ObsidianUITheme.primaryAccent,
              onChanged: (val) => setState(() => _keepMeLoggedIn = val ?? true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Form(
      key: _registerFormKey,
      child: Column(
        children: [
          TextFormField(
            controller: _regUsernameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'New Username',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.person_add_outlined, color: ObsidianUITheme.secondaryAccent),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            validator: (val) => val == null || val.trim().isEmpty ? 'Username is required' : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _regEmailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Email Address (Optional)',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.email_outlined, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _regTeamNumberController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Team Number',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.group_outlined, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Team number required';
              final n = int.tryParse(val.trim());
              if (n == null || n <= 0) return 'Must be a positive team number';
              return null;
            },
          ),
          const SizedBox(height: 16.0),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _regProgram,
            dropdownColor: ObsidianUITheme.surface,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Program',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.category_outlined, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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
            dropdownColor: ObsidianUITheme.surface,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'User Role',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.badge_outlined, color: ObsidianUITheme.secondaryAccent),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
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
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Password',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.lock_outline, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            validator: (val) => val == null || val.length < 4 ? 'Password must be at least 4 characters' : null,
          ),
          const SizedBox(height: 12.0),
          TextFormField(
            controller: _regConfirmPasswordController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Confirm Password',
              labelStyle: TextStyle(color: Colors.white60),
              prefixIcon: Icon(Icons.lock_reset_outlined, color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return 'Please confirm password';
              if (val != _regPasswordController.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 12.0),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep Me Logged In', style: TextStyle(color: Colors.white70, fontSize: 14.0)),
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
