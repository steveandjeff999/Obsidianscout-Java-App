import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ChatScreen extends StatefulWidget {
  final ApiService apiService;
  final String? initialChannel;
  final bool isVisible;
  final bool isBarsVisible;

  const ChatScreen({
    super.key,
    required this.apiService,
    this.initialChannel,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _isLoading = true;
  bool _isChatEnabled = true;
  String _currentGroup = 'general';
  List<String> _knownGroups = ['general'];
  Map<String, ChatGroupUnreadModel> _groupUnreads = {};
  List<ChatMessageModel> _messages = [];
  List<String> _mentionOptions = ['everyone', 'channel'];
  
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  Timer? _pollTimer;
  bool _isSending = false;

  // Autocomplete state for @mentions
  bool _showMentionDropdown = false;
  List<String> _filteredMentions = [];
  int _mentionTriggerIndex = -1;

  final List<String> _emojis = ['👍', '❤️', '🔥', '😂', '😮', '😢'];

  @override
  void initState() {
    super.initState();
    if (widget.initialChannel != null && widget.initialChannel!.trim().isNotEmpty) {
      _currentGroup = widget.initialChannel!.trim();
    }
    _messageController.addListener(_handleInputChanged);
    _initChat();
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialChannel != null &&
        widget.initialChannel != oldWidget.initialChannel &&
        widget.initialChannel!.trim().isNotEmpty) {
      setState(() {
        _currentGroup = widget.initialChannel!.trim();
        if (!_knownGroups.contains(_currentGroup)) {
          _knownGroups.add(_currentGroup);
        }
      });
      _loadMessagesAndUnreads(scrollToBottom: true);
    } else if (widget.isVisible && !oldWidget.isVisible) {
      _loadMessagesAndUnreads(scrollToBottom: false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.removeListener(_handleInputChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    setState(() => _isLoading = true);
    final enabled = await widget.apiService.fetchChatEnabled();
    if (!mounted) return;

    if (!enabled) {
      setState(() {
        _isChatEnabled = false;
        _isLoading = false;
      });
      return;
    }

    final groups = await widget.apiService.fetchChatGroups();
    final teamUsers = await widget.apiService.fetchChatTeamUsers();

    if (!mounted) return;

    setState(() {
      _isChatEnabled = true;
      _knownGroups = groups.isNotEmpty ? groups : ['general'];
      _mentionOptions = teamUsers.isNotEmpty ? teamUsers : ['everyone', 'channel'];
      if (widget.initialChannel != null && widget.initialChannel!.trim().isNotEmpty) {
        _currentGroup = widget.initialChannel!.trim();
        if (!_knownGroups.contains(_currentGroup)) {
          _knownGroups.add(_currentGroup);
        }
      } else if (!_knownGroups.contains(_currentGroup)) {
        _currentGroup = _knownGroups.first;
      }
    });

    await _loadMessagesAndUnreads(scrollToBottom: true);
    _startPolling();

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted && _isChatEnabled && widget.apiService.isOnline) {
        _loadMessagesAndUnreads(scrollToBottom: false);
      }
    });
  }

  Future<void> _loadMessagesAndUnreads({bool scrollToBottom = false}) async {
    final unreads = await widget.apiService.fetchChatUnreadStatus();
    final msgs = await widget.apiService.fetchChatMessages(_currentGroup);

    if (!mounted) return;

    setState(() {
      _groupUnreads = unreads;
      _messages = msgs;
    });

    if (scrollToBottom) {
      _scrollToBottom();
    }

    // Mark as read
    widget.apiService.markChatGroupRead(_currentGroup);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _switchGroup(String group) {
    if (_currentGroup == group) return;
    setState(() {
      _currentGroup = group;
      _messages = [];
      _showMentionDropdown = false;
    });
    _loadMessagesAndUnreads(scrollToBottom: true);
  }

  Future<void> _handleSendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    if (!widget.apiService.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot send messages in offline mode.'),
          backgroundColor: ObsidianUITheme.warningOrange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSending = true);
    _messageController.clear();
    setState(() => _showMentionDropdown = false);

    final success = await widget.apiService.sendChatMessage(_currentGroup, text);
    if (mounted) {
      setState(() => _isSending = false);
      if (success) {
        await _loadMessagesAndUnreads(scrollToBottom: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message.'),
            backgroundColor: ObsidianUITheme.errorRed,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _handleToggleReaction(String messageId, String emoji) async {
    if (!widget.apiService.isOnline) return;
    await widget.apiService.toggleChatReaction(messageId, emoji);
    await _loadMessagesAndUnreads(scrollToBottom: false);
  }

  void _showCreateGroupDialog() {
    final controller = TextEditingController();
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text('Create New Channel', style: TextStyle(color: primaryTextColor)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            hintText: 'Group name (e.g. strategy, scouting)',
            hintStyle: TextStyle(color: faintTextColor),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
            onPressed: () async {
              final raw = controller.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '');
              if (raw.isNotEmpty) {
                Navigator.of(ctx).pop();
                widget.apiService.createChatGroup(raw);
                if (!_knownGroups.contains(raw)) {
                  setState(() {
                    _knownGroups.add(raw);
                  });
                }
                _switchGroup(raw);
              }
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Handle @mentions autocomplete logic
  void _handleInputChanged() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (!selection.isValid || selection.isCollapsed == false) {
      if (_showMentionDropdown) setState(() => _showMentionDropdown = false);
      return;
    }

    final cursor = selection.baseOffset;
    final textUpToCursor = text.substring(0, cursor);

    int atIndex = -1;
    for (int i = cursor - 1; i >= 0; i--) {
      if (textUpToCursor[i] == '@') {
        if (i == 0 || textUpToCursor[i - 1] == ' ' || textUpToCursor[i - 1] == '\n') {
          atIndex = i;
          break;
        }
      }
    }

    if (atIndex != -1) {
      final query = textUpToCursor.substring(atIndex + 1);
      if (!query.contains('\n')) {
        final matches = _mentionOptions
            .where((opt) => opt.toLowerCase().contains(query.toLowerCase()))
            .toList();

        if (matches.isNotEmpty) {
          setState(() {
            _mentionTriggerIndex = atIndex;
            _filteredMentions = matches;
            _showMentionDropdown = true;
          });
          return;
        }
      }
    }

    if (_showMentionDropdown) {
      setState(() => _showMentionDropdown = false);
    }
  }

  void _insertMention(String option) {
    if (_mentionTriggerIndex == -1) return;
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursor = selection.baseOffset;

    final before = text.substring(0, _mentionTriggerIndex);
    final after = text.substring(cursor);
    final mentionText = '@$option ';

    _messageController.value = TextEditingValue(
      text: before + mentionText + after,
      selection: TextSelection.collapsed(offset: _mentionTriggerIndex + mentionText.length),
    );

    setState(() => _showMentionDropdown = false);
  }

  Color _getAvatarColor(String username) {
    int hue = 0;
    for (int i = 0; i < username.length; i++) {
      hue = (hue + username.codeUnitAt(i) * 37) % 360;
    }
    return HSLColor.fromAHSL(1.0, hue.toDouble(), 0.6, 0.45).toColor();
  }

  String _formatTimestamp(String raw) {
    try {
      // Ensure UTC interpretation: append 'Z' if no timezone info present
      final normalized = raw.endsWith('Z') || raw.contains('+') ? raw : '${raw}Z';
      final dt = DateTime.parse(normalized).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return raw;
    }
  }

  void _showReactionPicker(BuildContext context, String messageId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ObsidianUITheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _emojis.map((emoji) {
            return GestureDetector(
              onTap: () {
                Navigator.of(ctx).pop();
                _handleToggleReaction(messageId, emoji);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: const Center(
          child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
        ),
      );
    }

    if (!_isChatEnabled) {
      return Scaffold(
        backgroundColor: scaffoldBg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.warningOrange.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_outline_rounded, size: 56, color: ObsidianUITheme.warningOrange),
                ),
                const SizedBox(height: 20),
                Text(
                  'Team Chat is Disabled',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 10),
                Text(
                  'An administrator has turned off team chat. Contact your lead mentor in app settings to enable communications.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: secondaryTextColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentUsername = widget.apiService.savedUsername;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Column(
        children: [
          // Top Spacer for AppBar overlay
          const SizedBox(height: 96),

          // FIRST YPP Guidelines Reminder Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        const TextSpan(text: 'Youth Protection reminder: Please follow the '),
                        TextSpan(
                          text: 'FIRST Youth Protection Program (YPP) guidelines',
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.bold,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () async {
                              final url = Uri.parse('https://www.firstinspires.org/resource-library/youth-protection-policy');
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            },
                        ),
                        const TextSpan(text: '. Keep all chat communications respectful, safe, and positive.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Channel Selector Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: ObsidianUITheme.isDark(context) ? const Color(0x30121620) : const Color(0xF0F1F5F9),
            child: Row(
              children: [
                const Icon(Icons.tag_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: PopupMenuButton<String>(
                    color: surfaceColor,
                    onSelected: _switchGroup,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '# $_currentGroup',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, color: secondaryTextColor),
                      ],
                    ),
                    itemBuilder: (ctx) {
                      return _knownGroups.map((group) {
                        final unreadInfo = _groupUnreads[group];
                        final unreadCount = unreadInfo?.unreadCount ?? 0;
                        final mentionCount = unreadInfo?.mentionCount ?? 0;

                        return PopupMenuItem<String>(
                          value: group,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('# $group', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                              if (mentionCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('$mentionCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                )
                              else if (unreadCount > 0)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: ObsidianUITheme.primaryAccent, size: 22),
                  tooltip: 'Create Channel',
                  onPressed: _showCreateGroupDialog,
                ),
              ],
            ),
          ),

          // Messages List Area
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet in #$_currentGroup.\nBe the first to say hello!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, index) {
                      final msg = _messages[index];
                      final isMe = (currentUsername.isNotEmpty && msg.username.toLowerCase() == currentUsername.toLowerCase());
                      final initials = (msg.username.length >= 2 ? msg.username.substring(0, 2) : msg.username).toUpperCase();
                      final avatarColor = _getAvatarColor(msg.username);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe) ...[
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: avatarColor,
                                child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Container(
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.25)
                                      : (ObsidianUITheme.isDark(context) ? const Color(0x25FFFFFF) : ObsidianUITheme.getSurfaceColor(context)),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 2),
                                    bottomRight: Radius.circular(isMe ? 2 : 16),
                                  ),
                                  border: Border.all(
                                    color: isMe ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.5) : ObsidianUITheme.getBorderColor(context),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header: sender & time
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          msg.username,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: isMe ? ObsidianUITheme.primaryAccent : primaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatTimestamp(msg.createdAt),
                                          style: TextStyle(fontSize: 10, color: faintTextColor),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),

                                    // Content Text
                                    Text(
                                      msg.content,
                                      style: TextStyle(color: primaryTextColor, fontSize: 14, height: 1.3),
                                    ),

                                    // Reactions Bar
                                    if (msg.reactions.isNotEmpty || !isMe) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          ...msg.reactions.entries.where((e) => e.value.isNotEmpty).map((e) {
                                            final emoji = e.key;
                                            final users = e.value;
                                            final count = users.length;
                                            final hasReacted = users.contains(currentUsername);
                                            final userList = users.join(', ');

                                            return Tooltip(
                                              message: '$emoji  $userList',
                                              preferBelow: false,
                                              child: GestureDetector(
                                                onTap: isMe ? null : () => _handleToggleReaction(msg.id, emoji),
                                                onLongPress: () {
                                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Row(
                                                        children: [
                                                          Text(emoji, style: const TextStyle(fontSize: 16)),
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              'Reacted by: $userList',
                                                              style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w500),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      duration: const Duration(seconds: 3),
                                                      backgroundColor: surfaceColor,
                                                      behavior: SnackBarBehavior.floating,
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: hasReacted ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.3) : ObsidianUITheme.getBorderColor(context),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: hasReacted ? ObsidianUITheme.primaryAccent : Colors.transparent,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Text('$emoji $count', style: TextStyle(fontSize: 11, color: primaryTextColor)),
                                                ),
                                              ),
                                            );
                                          }),

                                          if (!isMe)
                                            GestureDetector(
                                              onTap: () => _showReactionPicker(context, msg.id),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: ObsidianUITheme.getBorderColor(context),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text('+', style: TextStyle(fontSize: 11, color: secondaryTextColor, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 10),
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: ObsidianUITheme.primaryAccent,
                                child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Autocomplete Mentions Dropdown Popover
          if (_showMentionDropdown && _filteredMentions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: ObsidianUITheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ObsidianUITheme.glassBorderLight, width: 1),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filteredMentions.length,
                itemBuilder: (ctx, idx) {
                  final mention = _filteredMentions[idx];
                  final isSpecial = mention == 'everyone' || mention == 'channel';
                  return ListTile(
                    dense: true,
                    title: Text(
                      '@$mention',
                      style: TextStyle(
                        color: isSpecial ? ObsidianUITheme.primaryAccent : Colors.white,
                        fontWeight: isSpecial ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () => _insertMention(mention),
                  );
                },
              ),
            ),

          // Bottom Chat Input Area
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            padding: EdgeInsets.fromLTRB(16.0, 12.0, 16.0, widget.isBarsVisible ? 134.0 : 16.0),
            color: ObsidianUITheme.isDark(context) ? const Color(0x30121620) : const Color(0xF0F1F5F9),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _inputFocusNode,
                    style: TextStyle(color: primaryTextColor, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: context.tr('contact.placeholder.message'),
                      hintStyle: TextStyle(color: faintTextColor, fontSize: 13),
                      filled: true,
                      fillColor: surfaceColor,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: ObsidianUITheme.primaryAccent,
                  ),
                  onPressed: _isSending ? null : _handleSendMessage,
                  icon: _isSending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
