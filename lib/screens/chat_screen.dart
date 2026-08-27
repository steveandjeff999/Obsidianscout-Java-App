import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _currentGroup = '';
  List<String> _knownGroups = [];
  Map<String, ChatGroupUnreadModel> _groupUnreads = {};
  List<ChatMessageModel> _messages = [];
  List<String> _mentionOptions = ['everyone', 'channel'];
  String? _currentUserRole;
  
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
    final role = await widget.apiService.fetchCurrentUserRole();

    if (!mounted) return;

    setState(() {
      _isChatEnabled = true;
      _currentUserRole = role;
      _knownGroups = groups.isNotEmpty ? groups : [];
      _mentionOptions = teamUsers.isNotEmpty ? teamUsers : ['everyone', 'channel'];
      if (widget.initialChannel != null && widget.initialChannel!.trim().isNotEmpty) {
        final requested = widget.initialChannel!.trim();
        // Only honour the push-notification channel if the user actually has access to it
        if (_knownGroups.contains(requested)) {
          _currentGroup = requested;
        } else {
          _currentGroup = _knownGroups.isNotEmpty ? _knownGroups.first : '';
        }
      } else if (!_knownGroups.contains(_currentGroup)) {
        _currentGroup = _knownGroups.isNotEmpty ? _knownGroups.first : '';
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
      if (mounted && _isChatEnabled && widget.apiService.isOnline && widget.isVisible) {
        _loadMessagesAndUnreads(scrollToBottom: false);
      }
    });
  }

  Future<void> _loadMessagesAndUnreads({bool scrollToBottom = false}) async {
    if (_currentGroup.isEmpty) return;
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

  void _showClearGroupDialog(String group) {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final messenger = ScaffoldMessenger.of(context);
    final msgCleared = context.tr('chat.messages_cleared');
    final errCleared = context.tr('chat.error_clear_channel');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(context.tr('chat.clear_messages'), style: TextStyle(color: primaryTextColor)),
        content: Text(
          context.tr('chat.clear_messages_confirm').replaceAll('{group}', group),
          style: TextStyle(color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('chat.cancel'), style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await widget.apiService.clearChatGroupMessages(group);
              if (!mounted) return;
              if (success) {
                if (_currentGroup == group) {
                  await _loadMessagesAndUnreads(scrollToBottom: true);
                }
                messenger.showSnackBar(
                  SnackBar(content: Text(msgCleared)),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(errCleared)),
                );
              }
            },
            child: Text(context.tr('chat.clear_messages'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog(String group) {
    if (_knownGroups.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('chat.cannot_delete_last'))),
      );
      return;
    }

    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final messenger = ScaffoldMessenger.of(context);
    final errDelete = context.tr('chat.error_delete_channel');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(context.tr('chat.delete_channel'), style: TextStyle(color: primaryTextColor)),
        content: Text(
          context.tr('chat.delete_channel_confirm').replaceAll('{group}', group),
          style: TextStyle(color: secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('chat.cancel'), style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await widget.apiService.deleteChatGroup(group);
              if (!mounted) return;
              if (success) {
                setState(() {
                  _knownGroups.remove(group);
                  if (_currentGroup == group) {
                    _currentGroup = _knownGroups.isNotEmpty ? _knownGroups.first : '';
                  }
                });
                await _initChat();
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(errDelete)),
                );
              }
            },
            child: Text(context.tr('chat.delete'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  void _showChannelSettingsModal(BuildContext context, String group) {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final messenger = ScaffoldMessenger.of(context);
    final msgSaved = context.tr('chat.permissions_saved');
    final errSaved = context.tr('chat.error_save_permissions');
    final errAdminRequired = context.tr('chat.admin_required');

    final availableRoles = [
      'ADMIN',
      'ANALYTICS',
      'SCOUT',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        List<String>? selectedRoles;
        List<String>? selectedUserIds;
        String memberFilter = '';
        String? adminError;

        return FutureBuilder<List<dynamic>>(
          future: Future.wait([
            widget.apiService.fetchChatGroupDetails(group),
            widget.apiService.fetchChatTeamMembers(),
          ]),
          builder: (ctx, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                padding: const EdgeInsets.all(32),
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }

            final details = snapshot.data?[0] as ChatGroupDetailsModel?;
            final teamMembers = (snapshot.data?[1] as List<ChatTeamMemberModel>?) ?? [];

            final initialRoles = details?.allowedRoles ?? [];
            final initialUserIds = details?.allowedUserIds ?? [];

            return StatefulBuilder(
              builder: (modalCtx, setModalState) {
                selectedRoles ??= List<String>.from(initialRoles);
                selectedUserIds ??= List<String>.from(initialUserIds);

                final filteredMembers = teamMembers.where((m) {
                  if (memberFilter.isEmpty) return true;
                  final q = memberFilter.toLowerCase();
                  return m.username.toLowerCase().contains(q) || m.role.toLowerCase().contains(q);
                }).toList();

                return Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '#$group ${context.tr('chat.channel_settings')}',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close_rounded, color: secondaryTextColor),
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView(
                          children: [
                            // Access Control Section
                            Text(
                              context.tr('chat.access_control'),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr('chat.access_control_desc'),
                              style: TextStyle(fontSize: 12, color: faintTextColor),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.tr('chat.allowed_roles'),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: availableRoles.map((role) {
                                final isSelected = selectedRoles!.contains(role);
                                return FilterChip(
                                  label: Text(
                                    role,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected ? Colors.white : primaryTextColor,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: ObsidianUITheme.primaryAccent,
                                  checkmarkColor: Colors.white,
                                  backgroundColor: ObsidianUITheme.isDark(context) ? const Color(0x30121620) : const Color(0xFFE2E8F0),
                                  onSelected: (val) {
                                    setModalState(() {
                                      if (val) {
                                        selectedRoles!.add(role);
                                      } else {
                                        selectedRoles!.remove(role);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.tr('chat.allowed_members'),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              style: TextStyle(fontSize: 13, color: primaryTextColor),
                              decoration: InputDecoration(
                                hintText: context.tr('chat.search_members'),
                                hintStyle: TextStyle(color: faintTextColor, fontSize: 13),
                                prefixIcon: Icon(Icons.search_rounded, size: 18, color: secondaryTextColor),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
                                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
                              ),
                              onChanged: (val) {
                                setModalState(() {
                                  memberFilter = val.trim();
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: filteredMembers.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          'No members found',
                                          style: TextStyle(color: faintTextColor, fontSize: 12),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: filteredMembers.length,
                                      itemBuilder: (ctx, i) {
                                        final m = filteredMembers[i];
                                        final isChecked = selectedUserIds!.contains(m.userId);
                                        return CheckboxListTile(
                                          value: isChecked,
                                          dense: true,
                                          title: Text(m.username, style: TextStyle(fontSize: 13, color: primaryTextColor)),
                                          subtitle: Text(m.role, style: TextStyle(fontSize: 11, color: faintTextColor)),
                                          activeColor: ObsidianUITheme.primaryAccent,
                                          onChanged: (val) {
                                            setModalState(() {
                                              if (val == true) {
                                                selectedUserIds!.add(m.userId);
                                              } else {
                                                selectedUserIds!.remove(m.userId);
                                              }
                                            });
                                          },
                                        );
                                      },
                                    ),
                            ),
                            const SizedBox(height: 20),
                            // Admin-required inline error
                            if (adminError != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.12),
                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        adminError!,
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Save permissions button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ObsidianUITheme.primaryAccent,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () async {
                                  final isRestricted = selectedRoles!.isNotEmpty || selectedUserIds!.isNotEmpty;
                                  final hasAdminRole = selectedRoles!.contains('ADMIN') || selectedRoles!.contains('SUPERADMIN');
                                  final hasAdminUser = selectedUserIds!.any((uid) {
                                    final member = teamMembers.where((m) => m.userId == uid).firstOrNull;
                                    if (member == null) return false;
                                    final roleUpper = member.role.trim().toUpperCase();
                                    return roleUpper == 'ADMIN' || roleUpper == 'SUPERADMIN';
                                  });

                                  if (isRestricted && !hasAdminRole && !hasAdminUser) {
                                    setModalState(() => adminError = errAdminRequired);
                                    return;
                                  }
                                  setModalState(() => adminError = null);

                                  final success = await widget.apiService.updateChatGroupPermissions(
                                    group,
                                    selectedRoles!,
                                    selectedUserIds!,
                                  );
                                  if (sheetCtx.mounted) {
                                    Navigator.of(sheetCtx).pop();
                                  }
                                  if (!mounted) return;
                                  if (success) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(msgSaved)),
                                    );
                                    await _initChat();
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(errSaved)),
                                    );
                                  }
                                },
                                child: Text(context.tr('chat.save_changes'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Danger Zone
                            Text(
                              context.tr('chat.danger_zone'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.redAccent),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.amber.shade700,
                                      side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.5)),
                                    ),
                                    icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                                    label: Text(context.tr('chat.clear_messages'), style: const TextStyle(fontSize: 12)),
                                    onPressed: () {
                                      Navigator.of(sheetCtx).pop();
                                      _showClearGroupDialog(group);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                                    ),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                    label: Text(context.tr('chat.delete_channel'), style: const TextStyle(fontSize: 12)),
                                    onPressed: _knownGroups.length <= 1
                                        ? null
                                        : () {
                                            Navigator.of(sheetCtx).pop();
                                            _showDeleteGroupDialog(group);
                                          },
                                  ),
                                ),
                              ],
                            ),
                            if (_knownGroups.length <= 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  context.tr('chat.cannot_delete_last_hint'),
                                  style: TextStyle(color: faintTextColor, fontSize: 11),
                                ),
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
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

  void _showMessageActions(BuildContext context, ChatMessageModel msg, bool isMe) {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: ObsidianUITheme.getBorderColor(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (!isMe)
                ListTile(
                  leading: const Icon(Icons.add_reaction_outlined, color: ObsidianUITheme.primaryAccent),
                  title: Text(context.tr('chat.add_reaction'), style: TextStyle(color: primaryTextColor)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showReactionPicker(context, msg.id);
                  },
                ),
              ListTile(
                leading: Icon(Icons.copy_rounded, color: secondaryTextColor),
                title: Text(context.tr('chat.copy_text'), style: TextStyle(color: primaryTextColor)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Clipboard.setData(ClipboardData(text: msg.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('chat.copied_to_clipboard')),
                      duration: const Duration(seconds: 2),
                      backgroundColor: ObsidianUITheme.primaryAccent,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: ObsidianUITheme.primaryAccent),
                  title: Text(context.tr('chat.edit_message'), style: TextStyle(color: primaryTextColor)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showEditMessageDialog(context, msg);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: ObsidianUITheme.errorRed),
                title: Text(context.tr('chat.delete_message'), style: const TextStyle(color: ObsidianUITheme.errorRed)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showDeleteMessageDialog(context, msg);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditMessageDialog(BuildContext context, ChatMessageModel msg) {
    final controller = TextEditingController(text: msg.content);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final messenger = ScaffoldMessenger.of(context);
    final errEdit = context.tr('chat.error_edit');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(context.tr('chat.edit_message'), style: TextStyle(color: primaryTextColor)),
        content: TextField(
          controller: controller,
          maxLines: 4,
          minLines: 1,
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            hintText: context.tr('chat.input_placeholder'),
            hintStyle: TextStyle(color: faintTextColor),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.getBorderColor(context))),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('chat.cancel'), style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.primaryAccent),
            onPressed: () async {
              final newContent = controller.text.trim();
              if (newContent.isNotEmpty && newContent != msg.content) {
                Navigator.of(ctx).pop();
                final success = await widget.apiService.editChatMessage(msg.id, newContent);
                if (mounted) {
                  if (success) {
                    await _loadMessagesAndUnreads(scrollToBottom: false);
                  } else {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(errEdit),
                        backgroundColor: ObsidianUITheme.errorRed,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                }
              } else if (newContent == msg.content) {
                Navigator.of(ctx).pop();
              }
            },
            child: Text(context.tr('chat.save'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteMessageDialog(BuildContext context, ChatMessageModel msg) {
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final messenger = ScaffoldMessenger.of(context);
    final errDelete = context.tr('chat.error_delete');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        title: Text(context.tr('chat.delete_message'), style: TextStyle(color: primaryTextColor)),
        content: Text(context.tr('chat.delete_confirm'), style: TextStyle(color: secondaryTextColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('chat.cancel'), style: TextStyle(color: secondaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await widget.apiService.deleteChatMessage(msg.id);
              if (mounted) {
                if (success) {
                  await _loadMessagesAndUnreads(scrollToBottom: false);
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(errDelete),
                      backgroundColor: ObsidianUITheme.errorRed,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            child: Text(context.tr('chat.delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
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
          const SizedBox(height: 4),

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
                        Flexible(
                          child: Text(
                            '# $_currentGroup',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, color: secondaryTextColor),
                      ],
                    ),
                    itemBuilder: (ctx) {
                      final isAdmin = _currentUserRole?.toUpperCase() == 'ADMIN' || _currentUserRole?.toUpperCase() == 'SUPERADMIN';
                      return _knownGroups.map((group) {
                        final unreadInfo = _groupUnreads[group];
                        final unreadCount = unreadInfo?.unreadCount ?? 0;
                        final mentionCount = unreadInfo?.mentionCount ?? 0;

                        return PopupMenuItem<String>(
                          value: group,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '# $group',
                                  style: TextStyle(
                                    color: group == _currentGroup ? ObsidianUITheme.primaryAccent : primaryTextColor,
                                    fontWeight: group == _currentGroup ? FontWeight.bold : FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (mentionCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(left: 6),
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
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (isAdmin) ...[
                                InkWell(
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _showChannelSettingsModal(context, group);
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.settings_outlined, size: 18, color: ObsidianUITheme.primaryAccent),
                                  ),
                                ),
                                if (_knownGroups.length > 1)
                                  InkWell(
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      _showDeleteGroupDialog(group);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                if (_currentUserRole?.toUpperCase() == 'ADMIN' || _currentUserRole?.toUpperCase() == 'SUPERADMIN')
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: ObsidianUITheme.primaryAccent, size: 22),
                    tooltip: context.tr('chat.channel_settings'),
                    onPressed: () => _showChannelSettingsModal(context, _currentGroup),
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
                    physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
                              child: GestureDetector(
                                onLongPress: () => _showMessageActions(context, msg, isMe),
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
                                      // Header: sender, time, edited indicator, actions
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
                                          if (msg.isEdited) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              context.tr('chat.edited'),
                                              style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: faintTextColor),
                                            ),
                                          ],
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () => _showMessageActions(context, msg, isMe),
                                            child: Icon(Icons.more_horiz_rounded, size: 14, color: faintTextColor),
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
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
                      hintText: context.tr('chat.input_placeholder'),
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
