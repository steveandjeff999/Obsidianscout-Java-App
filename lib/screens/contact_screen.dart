import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

class ContactScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const ContactScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _teamController;
  final TextEditingController _messageController = TextEditingController();

  String _selectedType = 'BUG_REPORT';
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    final user = widget.apiService.currentUser;
    _nameController = TextEditingController(text: user?.username ?? widget.apiService.savedUsername);
    _emailController = TextEditingController(text: user?.email ?? '');
    _teamController = TextEditingController(
      text: user?.teamNumber != null && user!.teamNumber > 0
          ? user.teamNumber.toString()
          : '',
    );
  }

  @override
  void didUpdateWidget(covariant ContactScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _syncUserFields();
    }
  }

  void _syncUserFields() {
    final user = widget.apiService.currentUser;
    if (_nameController.text.isEmpty && user?.username.isNotEmpty == true) {
      _nameController.text = user!.username;
    }
    if (_emailController.text.isEmpty && user?.email?.isNotEmpty == true) {
      _emailController.text = user!.email!;
    }
    if (_teamController.text.isEmpty && user?.teamNumber != null && user!.teamNumber > 0) {
      _teamController.text = user.teamNumber.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _teamController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() => _isSending = true);

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final message = _messageController.text.trim();

    final response = await widget.apiService.sendContactMessage(
      type: _selectedType,
      name: name,
      replyToEmail: email.isNotEmpty ? email : null,
      message: message,
    );

    if (!mounted) return;

    setState(() => _isSending = false);

    if (response.success) {
      _messageController.clear();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr(
                    'contact.success',
                    'Your message has been sent successfully to obsidianscoutfrc@gmail.com!',
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      String errorMsg;
      if (response.statusCode == 503) {
        errorMsg = context.tr(
          'contact.error.smtp',
          'SMTP email configuration is missing or incorrect. Please contact your team admin.',
        );
      } else {
        final detail = response.message ?? 'Unknown error';
        errorMsg = '${context.tr('contact.error.generic', 'An error occurred while sending the message: ')}$detail';
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: ObsidianUITheme.errorRed,
          duration: const Duration(seconds: 6),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  errorMsg,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final cardBg = isDark ? const Color(0x331E293B) : const Color(0x66FFFFFF);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Notice Card
                ObsidianGlassCard(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3),
                            width: 1.0,
                          ),
                        ),
                        child: const Icon(
                          Icons.contact_support_rounded,
                          color: ObsidianUITheme.primaryAccent,
                          size: 26.0,
                        ),
                      ),
                      const SizedBox(width: 14.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('contact.title', 'Contact Us'),
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 3.0),
                            Text(
                              context.tr(
                                'contact.notice',
                                'Submit a bug report, feature request, or general feedback.',
                              ),
                              style: TextStyle(
                                fontSize: 13.0,
                                color: secondaryTextColor,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),

                // Main Contact Form Card
                ObsidianGlassCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Name Field
                        _buildFieldLabel(
                          context.tr('contact.label.name', 'Your Name'),
                          primaryTextColor,
                        ),
                        const SizedBox(height: 6.0),
                        TextFormField(
                          controller: _nameController,
                          style: TextStyle(color: primaryTextColor, fontSize: 14.0),
                          decoration: InputDecoration(
                            hintText: context.tr('contact.label.name', 'Your Name'),
                            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20.0),
                            filled: true,
                            fillColor: cardBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: const BorderSide(color: ObsidianUITheme.primaryAccent, width: 1.5),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16.0),

                        // Reply-To Email Field
                        _buildFieldLabel(
                          context.tr('contact.label.email', 'Reply-To Email Address'),
                          primaryTextColor,
                        ),
                        const SizedBox(height: 6.0),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(color: primaryTextColor, fontSize: 14.0),
                          decoration: InputDecoration(
                            hintText: 'name@example.com',
                            prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20.0),
                            filled: true,
                            fillColor: cardBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: const BorderSide(color: ObsidianUITheme.primaryAccent, width: 1.5),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a reply-to email address';
                            }
                            final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                            if (!emailRegex.hasMatch(value.trim())) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16.0),

                        // Team Number Field (Read-only / Disabled style)
                        _buildFieldLabel(
                          context.tr('contact.label.team', 'Team Number'),
                          primaryTextColor,
                        ),
                        const SizedBox(height: 6.0),
                        TextFormField(
                          controller: _teamController,
                          enabled: false,
                          style: TextStyle(
                            color: primaryTextColor.withValues(alpha: 0.65),
                            fontSize: 14.0,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.tag_rounded,
                              size: 20.0,
                              color: secondaryTextColor.withValues(alpha: 0.6),
                            ),
                            filled: true,
                            fillColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.03),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor.withValues(alpha: 0.5)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16.0),

                        // Submission Type Field
                        _buildFieldLabel(
                          context.tr('contact.label.type', 'Submission Type'),
                          primaryTextColor,
                        ),
                        const SizedBox(height: 6.0),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedType,
                          dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                          style: TextStyle(color: primaryTextColor, fontSize: 14.0),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.category_outlined, size: 20.0),
                            filled: true,
                            fillColor: cardBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: const BorderSide(color: ObsidianUITheme.primaryAccent, width: 1.5),
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'BUG_REPORT',
                              child: Text(context.tr('contact.type.bug_report', 'Bug Report')),
                            ),
                            DropdownMenuItem(
                              value: 'FEATURE_REQUEST',
                              child: Text(context.tr('contact.type.feature_request', 'Feature Request')),
                            ),
                            DropdownMenuItem(
                              value: 'OTHER',
                              child: Text(context.tr('contact.type.other', 'Other')),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedType = val);
                            }
                          },
                        ),
                        const SizedBox(height: 16.0),

                        // Message Textarea Field
                        _buildFieldLabel(
                          context.tr('contact.label.message', 'Message'),
                          primaryTextColor,
                        ),
                        const SizedBox(height: 6.0),
                        TextFormField(
                          controller: _messageController,
                          minLines: 6,
                          maxLines: 12,
                          style: TextStyle(color: primaryTextColor, fontSize: 14.0),
                          decoration: InputDecoration(
                            hintText: context.tr(
                              'contact.placeholder.message',
                              'Please describe your bug, feature request, or feedback here...',
                            ),
                            hintStyle: TextStyle(color: secondaryTextColor.withValues(alpha: 0.6), fontSize: 13.5),
                            filled: true,
                            fillColor: cardBg,
                            contentPadding: const EdgeInsets.all(14.0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.0),
                              borderSide: const BorderSide(color: ObsidianUITheme.primaryAccent, width: 1.5),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a message';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24.0),

                        // Submit Button
                        SizedBox(
                          height: 48.0,
                          child: ElevatedButton(
                            onPressed: _isSending ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ObsidianUITheme.primaryAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5),
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              elevation: 2.0,
                            ),
                            child: _isSending
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 18.0,
                                        height: 18.0,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      const SizedBox(width: 10.0),
                                      Text(
                                        context.tr('contact.btn.sending', 'Sending...'),
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.send_rounded, size: 18.0),
                                      const SizedBox(width: 8.0),
                                      Text(
                                        context.tr('contact.btn.send', 'Send Message'),
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
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
                const SizedBox(height: 32.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13.0,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.2,
      ),
    );
  }
}
