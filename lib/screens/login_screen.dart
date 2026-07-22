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
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _serverUrlController;
  final TextEditingController _usernameController = TextEditingController(text: 'admin');
  final TextEditingController _passwordController = TextEditingController(text: 'changeme');
  final TextEditingController _teamNumberController = TextEditingController(text: '0');

  String _selectedProgram = 'FRC';
  bool _keepMeLoggedIn = true;
  bool _isLoggingIn = false;
  bool _showServerConfig = false;

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
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isLoggingIn = true);

    // Save server URL configuration
    await widget.apiService.setServerUrl(_serverUrlController.text.trim());

    final success = await widget.apiService.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
      teamNumber: int.tryParse(_teamNumberController.text.trim()) ?? 0,
      program: _selectedProgram,
      keepMeLoggedIn: _keepMeLoggedIn,
    );

    setState(() => _isLoggingIn = false);

    if (mounted) {
      if (success) {
        widget.onLoginSuccess();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to authenticate with Obsidianscout server. Please check credentials & server URL.'),
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
            child: Form(
              key: _formKey,
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
                  ObsidianGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Server URL / Settings Toggle Row
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
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Server URL is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12.0),
                        ],
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 8.0),
                        TextFormField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            labelStyle: TextStyle(color: Colors.white60),
                            prefixIcon: Icon(Icons.person_outline, color: Colors.white70),
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          ),
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
                        // Program Selection (FRC / FTC)
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
                  ),
                  const SizedBox(height: 16.0),
                  ObsidianGlassCard(
                    onTap: _isLoggingIn ? null : _handleLogin,
                    child: Center(
                      child: _isLoggingIn
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.login_rounded, color: Colors.white),
                                SizedBox(width: 10.0),
                                Text(
                                  'CONNECT & LOGIN',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.0, color: Colors.white),
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
    );
  }
}
