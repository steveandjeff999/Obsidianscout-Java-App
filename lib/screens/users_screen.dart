import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../services/image_utils.dart';
import '../theme/obsidian_responsive.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/obsidian_user_avatar.dart';

class UsersScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const UsersScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final List<UserModel> _users = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _errorMessage;

  // Pagination & Filtering state
  static const int _limit = 50;
  int _offset = 0;
  String _searchQuery = '';
  String _teamFilter = '';
  String _programFilter = '';
  String _roleFilter = '';
  String _sortBy = 'team'; // 'username', 'email', 'team', 'role', 'created', 'lastLogin'
  String _sortDir = 'asc'; // 'asc', 'desc'

  Timer? _debounceTimer;

  // Create User Form Controllers
  final _createFormKey = GlobalKey<FormState>();
  final _createUsernameController = TextEditingController();
  final _createEmailController = TextEditingController();
  final _createTeamController = TextEditingController();
  final _createPasswordController = TextEditingController();
  String _createRole = 'SCOUT';
  bool _isCreatingUser = false;
  bool _isCreateFormExpanded = false;

  // Filter Controllers
  final _searchController = TextEditingController();
  final _teamFilterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initDefaults();
    _loadUsers();
  }

  void _initDefaults() {
    final caller = widget.apiService.currentUser;
    final isSuperAdmin = caller?.isSuperAdmin ?? (widget.apiService.currentUserRole == 'SUPERADMIN');
    if (!isSuperAdmin && caller != null) {
      _createTeamController.text = caller.teamNumber.toString();
    }
  }

  @override
  void didUpdateWidget(covariant UsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadUsers();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _createUsernameController.dispose();
    _createEmailController.dispose();
    _createTeamController.dispose();
    _createPasswordController.dispose();
    _searchController.dispose();
    _teamFilterController.dispose();
    super.dispose();
  }

  bool get _isSuperAdmin {
    final caller = widget.apiService.currentUser;
    return caller?.isSuperAdmin ?? (widget.apiService.currentUserRole == 'SUPERADMIN');
  }

  bool get _isAdmin {
    final caller = widget.apiService.currentUser;
    return _isSuperAdmin || (caller?.isAdmin ?? (widget.apiService.currentUserRole == 'ADMIN'));
  }

  Future<void> _loadUsers({bool append = false}) async {
    if (!_isAdmin) {
      setState(() => _isLoading = false);
      return;
    }

    if (!append) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _offset = 0;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final teamNum = int.tryParse(_teamFilter.trim());
      final res = await widget.apiService.getAdminUsers(
        q: _searchQuery.isNotEmpty ? _searchQuery : null,
        teamNumber: _isSuperAdmin ? teamNum : null,
        program: _isSuperAdmin && _programFilter.isNotEmpty ? _programFilter : null,
        role: _roleFilter.isNotEmpty ? _roleFilter : null,
        limit: _limit,
        offset: _offset,
        sortBy: _sortBy,
        sortDir: _sortDir,
      );

      if (!mounted) return;

      if (res.isSuccess && res.data != null) {
        final fetched = res.data!;
        setState(() {
          if (!append) {
            _users.clear();
          }
          _users.addAll(fetched);
          _offset += fetched.length;
          _hasMore = fetched.length == _limit;
          _isLoading = false;
          _isLoadingMore = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
          if (!append) {
            _errorMessage = res.message ?? 'Failed to load users';
          }
        });
        if (append && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.message ?? 'Failed to load more users')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (!append) {
          _errorMessage = e.toString();
        }
      });
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _searchQuery = val.trim();
      _loadUsers(append: false);
    });
  }

  void _onTeamFilterChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _teamFilter = val.trim();
      _loadUsers(append: false);
    });
  }

  void _resetFilters() {
    setState(() {
      _searchQuery = '';
      _teamFilter = '';
      _programFilter = '';
      _roleFilter = '';
      _searchController.clear();
      _teamFilterController.clear();
    });
    _loadUsers(append: false);
  }

  void _toggleSort(String column) {
    setState(() {
      if (_sortBy == column) {
        _sortDir = _sortDir == 'asc' ? 'desc' : 'asc';
      } else {
        _sortBy = column;
        _sortDir = (column == 'created' || column == 'lastLogin') ? 'desc' : 'asc';
      }
    });
    _loadUsers(append: false);
  }

  Future<void> _handleCreateUser() async {
    if (!_createFormKey.currentState!.validate()) return;

    final caller = widget.apiService.currentUser;
    final teamNum = _isSuperAdmin
        ? (int.tryParse(_createTeamController.text.trim()) ?? caller?.teamNumber ?? 0)
        : (caller?.teamNumber ?? 0);

    if (teamNum <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a valid team number')),
      );
      return;
    }

    setState(() => _isCreatingUser = true);

    final res = await widget.apiService.createAdminUser(
      username: _createUsernameController.text.trim(),
      teamNumber: teamNum,
      password: _createPasswordController.text,
      email: _createEmailController.text.trim(),
      program: caller?.program ?? widget.apiService.currentProgram,
      role: _createRole,
    );

    if (!mounted) return;
    setState(() => _isCreatingUser = false);

    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(res.message ?? 'User created successfully'),
        ),
      );
      _createUsernameController.clear();
      _createEmailController.clear();
      _createPasswordController.clear();
      if (!_isSuperAdmin && caller != null) {
        _createTeamController.text = caller.teamNumber.toString();
      } else {
        _createTeamController.clear();
      }
      setState(() {
        _createRole = 'SCOUT';
      });
      _loadUsers(append: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(res.message ?? 'Failed to create user'),
        ),
      );
    }
  }

  Future<void> _openEditModal(UserModel user) async {
    final caller = widget.apiService.currentUser;
    final callerRole = caller?.role ?? widget.apiService.currentUserRole;
    final canEdit = _isSuperAdmin || (!user.isSuperAdmin && user.teamNumber == caller?.teamNumber);

    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to edit this user')),
      );
      return;
    }

    final editUsernameCtrl = TextEditingController(text: user.username);
    final editEmailCtrl = TextEditingController(text: user.email ?? '');
    final editPasswordCtrl = TextEditingController();
    String editRole = user.role.toUpperCase();
    if (editRole.isEmpty) editRole = 'SCOUT';

    // Track pending avatar: null when explicitly removed, string when new photo uploaded, or null initially
    String? pendingAvatar = user.profilePicture;
    bool clearAvatar = false;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final isDesktop = ObsidianResponsive.isDesktop(dialogCtx, overrideMode: widget.apiService.uiMode);
            final textColor = ObsidianUITheme.getPrimaryTextColor(dialogCtx);
            final subColor = ObsidianUITheme.getSecondaryTextColor(dialogCtx);
            final cardBg = ObsidianUITheme.getSurfaceColor(dialogCtx);

            final canChangeUsername = _isSuperAdmin;
            final canChangeRole = _isSuperAdmin || (callerRole == 'ADMIN' && !user.isSuperAdmin);

            return Dialog(
              backgroundColor: cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: isDesktop ? 500 : double.infinity,
                constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.manage_accounts_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              dialogCtx.tr('users.edit_user', 'Edit User'),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    // Scrollable form
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar preview & actions
                            Center(
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: isSaving ? null : () async {
                                      final res = await ImageProcessingUtils.pickAndProcessAvatar(
                                        source: ImageSource.gallery,
                                      );
                                      if (res != null) {
                                        setModalState(() {
                                          pendingAvatar = res.dataUrl;
                                          clearAvatar = false;
                                        });
                                      }
                                    },
                                    child: Stack(
                                      children: [
                                        ObsidianUserAvatar(
                                          profilePicture: clearAvatar ? null : pendingAvatar,
                                          username: editUsernameCtrl.text.isNotEmpty ? editUsernameCtrl.text : user.username,
                                          size: 80,
                                          serverUrl: widget.apiService.serverUrl,
                                          borderWidth: 2,
                                          borderColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.5),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: ObsidianUITheme.primaryAccent,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: cardBg, width: 2),
                                            ),
                                            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        icon: const Icon(Icons.photo_library_rounded, size: 16),
                                        label: Text(dialogCtx.tr('config.upload_photo', 'Upload photo'), style: const TextStyle(fontSize: 12)),
                                        onPressed: isSaving ? null : () async {
                                          final res = await ImageProcessingUtils.pickAndProcessAvatar(
                                            source: ImageSource.gallery,
                                          );
                                          if (res != null) {
                                            setModalState(() {
                                              pendingAvatar = res.dataUrl;
                                              clearAvatar = false;
                                            });
                                          }
                                        },
                                      ),
                                      if ((pendingAvatar != null && !clearAvatar)) ...[
                                        const SizedBox(width: 8),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                          label: Text(dialogCtx.tr('config.remove', 'Remove'), style: const TextStyle(fontSize: 12)),
                                          onPressed: isSaving ? null : () {
                                            setModalState(() {
                                              pendingAvatar = null;
                                              clearAvatar = true;
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Username
                            Text(dialogCtx.tr('index.username', 'Username'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subColor)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: editUsernameCtrl,
                              readOnly: !canChangeUsername,
                              decoration: InputDecoration(
                                hintText: 'Username',
                                isDense: true,
                                helperText: !canChangeUsername ? 'Only superadmins can change usernames' : null,
                                prefixIcon: const Icon(Icons.person_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Email
                            Text(dialogCtx.tr('index.email', 'Email'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subColor)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: editEmailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'scout@example.com',
                                isDense: true,
                                prefixIcon: Icon(Icons.email_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // New Password
                            Text(dialogCtx.tr('reset-password.new_password', 'New Password'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subColor)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: editPasswordCtrl,
                              obscureText: true,
                              decoration: InputDecoration(
                                hintText: '••••••••',
                                isDense: true,
                                helperText: dialogCtx.tr('users.leave_blank_to_keep_the_curren', 'Leave blank to keep current password.'),
                                helperStyle: TextStyle(fontSize: 11, color: subColor),
                                prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Role selection (if permitted)
                            if (canChangeRole) ...[
                              Text(dialogCtx.tr('index.role', 'Role'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subColor)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String>(
                                initialValue: editRole,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  prefixIcon: Icon(Icons.badge_rounded, size: 20),
                                ),
                                dropdownColor: cardBg,
                                items: [
                                  const DropdownMenuItem(value: 'SCOUT', child: Text('Scout')),
                                  const DropdownMenuItem(value: 'ANALYTICS', child: Text('Analytics')),
                                  const DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                                  if (_isSuperAdmin)
                                    const DropdownMenuItem(value: 'SUPERADMIN', child: Text('Super Admin')),
                                ],
                                onChanged: isSaving ? null : (val) {
                                  if (val != null) {
                                    setModalState(() => editRole = val);
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSaving ? null : () => Navigator.of(dialogCtx).pop(),
                          child: Text(dialogCtx.tr('events.cancel', 'Cancel')),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ObsidianUITheme.primaryAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: isSaving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                          label: Text(
                            dialogCtx.tr('users.save_changes', 'Save changes'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final newUsername = editUsernameCtrl.text.trim();
                                  final newEmail = editEmailCtrl.text.trim();
                                  final newPassword = editPasswordCtrl.text;

                                  final navigator = Navigator.of(dialogCtx);
                                  final messenger = ScaffoldMessenger.of(context);

                                  setModalState(() => isSaving = true);

                                  final res = await widget.apiService.updateAdminUser(
                                    user.id,
                                    username: canChangeUsername && newUsername != user.username ? newUsername : null,
                                    email: newEmail,
                                    password: newPassword.isNotEmpty ? newPassword : null,
                                    role: canChangeRole && editRole != user.role ? editRole : null,
                                    profilePicture: (!clearAvatar && pendingAvatar != null && pendingAvatar != user.profilePicture)
                                        ? pendingAvatar
                                        : null,
                                    clearProfilePicture: clearAvatar,
                                  );

                                  if (!mounted) return;
                                  setModalState(() => isSaving = false);

                                  if (res.isSuccess) {
                                    if (dialogCtx.mounted) {
                                      navigator.pop();
                                    }
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.green.shade700,
                                        content: Text(res.message ?? 'User updated successfully'),
                                      ),
                                    );
                                    _loadUsers(append: false);
                                  } else {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.redAccent,
                                        content: Text(res.message ?? 'Failed to update user'),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleDeleteUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text(context.tr('users.delete_user', 'Delete User')),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the user "${user.username}"? Their submitted scouting data will be preserved under \'Deleted User\' on their team.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('events.cancel', 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('users.delete', 'Delete'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final caller = widget.apiService.currentUser;
    final isSelf = user.id == caller?.id;

    final res = await widget.apiService.deleteAdminUser(user.id);
    if (!mounted) return;

    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(res.message ?? 'User deleted successfully'),
        ),
      );
      if (isSelf) {
        await widget.apiService.logout();
      } else {
        _loadUsers(append: false);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(res.message ?? 'Failed to delete user'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return _buildAdminLockedScreen();
    }

    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);
    final textColor = ObsidianUITheme.getPrimaryTextColor(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadUsers(append: false),
          color: ObsidianUITheme.primaryAccent,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 24 : 16,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Screen Title Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
                            ),
                            child: Icon(Icons.manage_accounts_rounded, color: ObsidianUITheme.primaryAccent, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.tr('users.title', 'User Management'),
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
                                ),
                                Text(
                                  _isSuperAdmin
                                      ? 'Manage user accounts and role permissions across all teams'
                                      : 'Manage user accounts and roles on your team',
                                  style: TextStyle(fontSize: 13, color: ObsidianUITheme.getSecondaryTextColor(context)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Create User Collapsible Section
                      _buildCreateUserCard(isDesktop),
                      const SizedBox(height: 16),

                      // Search & Filter Controls Card
                      _buildFilterBar(isDesktop),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Users List / Table
              if (_isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
                  ),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: textColor, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                            onPressed: () => _loadUsers(append: false),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_users.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.group_off_rounded, size: 48, color: ObsidianUITheme.getSecondaryTextColor(context)),
                          const SizedBox(height: 12),
                          Text(
                            'No users found.',
                            style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 16),
                  sliver: isDesktop ? SliverToBoxAdapter(child: _buildDesktopTable()) : _buildMobileList(),
                ),

              // Load More / Bottom Spacing
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: _hasMore
                      ? Center(
                          child: _isLoadingMore
                              ? CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)
                              : ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ObsidianUITheme.getSurfaceColor(context),
                                    side: BorderSide(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  ),
                                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                                  label: Text(context.tr('users.load_more', 'Load More')),
                                  onPressed: () => _loadUsers(append: true),
                                ),
                        )
                      : const SizedBox(height: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminLockedScreen() {
    final textColor = ObsidianUITheme.getPrimaryTextColor(context);
    final subColor = ObsidianUITheme.getSecondaryTextColor(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ObsidianGlassCard(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_rounded, color: Colors.redAccent, size: 48),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('config.admin_only', 'Admin only'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('users.notice', 'You need admin access to manage users.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: subColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateUserCard(bool isDesktop) {
    final textColor = ObsidianUITheme.getPrimaryTextColor(context);
    final subColor = ObsidianUITheme.getSecondaryTextColor(context);

    return ObsidianGlassCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _isCreateFormExpanded,
          onExpansionChanged: (expanded) => setState(() => _isCreateFormExpanded = expanded),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.person_add_alt_1_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
          ),
          title: Text(
            context.tr('users.create_user', 'Create user'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
          ),
          subtitle: Text(
            'Add a new user to your team',
            style: TextStyle(fontSize: 12, color: subColor),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Form(
                key: _createFormKey,
                child: Column(
                  children: [
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildUsernameField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildEmailField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildTeamField()),
                        ],
                      )
                    else ...[
                      _buildUsernameField(),
                      const SizedBox(height: 12),
                      _buildEmailField(),
                      const SizedBox(height: 12),
                      _buildTeamField(),
                    ],
                    const SizedBox(height: 12),
                    if (isDesktop)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildPasswordField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildRoleDropdown()),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: _buildCreateSubmitButton(),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildPasswordField(),
                      const SizedBox(height: 12),
                      _buildRoleDropdown(),
                      const SizedBox(height: 16),
                      _buildCreateSubmitButton(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('index.username', 'Username'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextFormField(
          controller: _createUsernameController,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Username is required' : null,
          decoration: const InputDecoration(
            hintText: 'e.g. scout_john',
            isDense: true,
            prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('index.email', 'Email'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextFormField(
          controller: _createEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'scout@example.com',
            isDense: true,
            prefixIcon: Icon(Icons.email_outlined, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('pitdata.csv.team_number', 'Team Number'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextFormField(
          controller: _createTeamController,
          readOnly: !_isSuperAdmin,
          keyboardType: TextInputType.number,
          validator: (v) => (v == null || int.tryParse(v.trim()) == null) ? 'Valid team # required' : null,
          decoration: InputDecoration(
            hintText: 'e.g. 254',
            isDense: true,
            prefixIcon: const Icon(Icons.tag_rounded, size: 18),
            helperText: !_isSuperAdmin ? 'Locked to your team' : null,
            helperStyle: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('index.password', 'Password'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextFormField(
          controller: _createPasswordController,
          obscureText: true,
          validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
          decoration: const InputDecoration(
            hintText: '••••••••',
            isDense: true,
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('index.role', 'Role'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: _createRole,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.badge_outlined, size: 18),
          ),
          dropdownColor: ObsidianUITheme.getSurfaceColor(context),
          items: [
            const DropdownMenuItem(value: 'SCOUT', child: Text('Scout')),
            const DropdownMenuItem(value: 'ANALYTICS', child: Text('Analytics')),
            const DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
            if (_isSuperAdmin)
              const DropdownMenuItem(value: 'SUPERADMIN', child: Text('Super Admin')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _createRole = val);
          },
        ),
      ],
    );
  }

  Widget _buildCreateSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: ObsidianUITheme.primaryAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: _isCreatingUser
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
        label: Text(
          context.tr('users.create_user', 'Create user'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: _isCreatingUser ? null : _handleCreateUser,
      ),
    );
  }

  Widget _buildFilterBar(bool isDesktop) {
    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                const SizedBox(width: 8),
                Text(
                  context.tr('users.current_users', 'Current users'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: ObsidianUITheme.getPrimaryTextColor(context),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: Text(context.tr('users.reset', 'Reset')),
                  onPressed: _resetFilters,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Username Search
                SizedBox(
                  width: isDesktop ? 220 : double.infinity,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: context.tr('users.search_username', 'Search Username'),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),

                // Team Filter (SuperAdmin only)
                if (_isSuperAdmin)
                  SizedBox(
                    width: isDesktop ? 140 : double.infinity,
                    child: TextField(
                      controller: _teamFilterController,
                      keyboardType: TextInputType.number,
                      onChanged: _onTeamFilterChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: context.tr('users.filter_team', 'Filter Team'),
                        prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                      ),
                    ),
                  ),

                // Program Filter (SuperAdmin only)
                if (_isSuperAdmin)
                  SizedBox(
                    width: isDesktop ? 150 : double.infinity,
                    child: DropdownButtonFormField<String>(
                      initialValue: _programFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.category_rounded, size: 18),
                      ),
                      dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Programs')),
                        DropdownMenuItem(value: 'FRC', child: Text('FRC')),
                        DropdownMenuItem(value: 'FTC', child: Text('FTC')),
                      ],
                      onChanged: (val) {
                        setState(() => _programFilter = val ?? '');
                        _loadUsers(append: false);
                      },
                    ),
                  ),

                // Role Filter
                SizedBox(
                  width: isDesktop ? 180 : double.infinity,
                  child: DropdownButtonFormField<String>(
                    initialValue: _roleFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.badge_rounded, size: 18),
                    ),
                    dropdownColor: ObsidianUITheme.getSurfaceColor(context),
                    items: [
                      DropdownMenuItem(value: '', child: Text(context.tr('users.all_roles', 'All Roles'))),
                      const DropdownMenuItem(value: 'SCOUT', child: Text('Scout')),
                      const DropdownMenuItem(value: 'ANALYTICS', child: Text('Analytics')),
                      DropdownMenuItem(value: 'ADMIN', child: Text(context.tr('index.admin', 'Admin'))),
                      if (_isSuperAdmin)
                        DropdownMenuItem(value: 'SUPERADMIN', child: Text(context.tr('users.super_admin', 'Super Admin'))),
                    ],
                    onChanged: (val) {
                      setState(() => _roleFilter = val ?? '');
                      _loadUsers(append: false);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable() {
    final caller = widget.apiService.currentUser;
    final headerTextColor = ObsidianUITheme.getPrimaryTextColor(context);

    return ObsidianGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(
              ObsidianUITheme.primaryAccent.withValues(alpha: 0.08),
            ),
            columns: [
              DataColumn(
                label: const Text('User'),
                onSort: (_, __) => _toggleSort('username'),
              ),
              DataColumn(
                label: const Text('Email'),
                onSort: (_, __) => _toggleSort('email'),
              ),
              DataColumn(
                label: const Text('Team'),
                onSort: (_, __) => _toggleSort('team'),
              ),
              DataColumn(
                label: const Text('Role'),
                onSort: (_, __) => _toggleSort('role'),
              ),
              DataColumn(
                label: const Text('Created'),
                onSort: (_, __) => _toggleSort('created'),
              ),
              DataColumn(
                label: const Text('Last Login'),
                onSort: (_, __) => _toggleSort('lastLogin'),
              ),
              const DataColumn(label: Text('Actions')),
            ],
            rows: _users.map((user) {
              final canEdit = _isSuperAdmin || (!user.isSuperAdmin && user.teamNumber == caller?.teamNumber);
              final teamDisplay = _isSuperAdmin ? '[${user.program}] ${user.teamNumber}' : '${user.teamNumber}';
              final createdDisplay = _formatDate(user.createdAt);
              final lastLoginDisplay = _formatDate(user.lastLogin) ?? 'Never';

              return DataRow(
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ObsidianUserAvatar(
                          profilePicture: user.profilePicture,
                          username: user.username,
                          size: 32,
                          serverUrl: widget.apiService.serverUrl,
                        ),
                        const SizedBox(width: 10),
                        Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      user.email?.isNotEmpty == true ? user.email! : 'None',
                      style: TextStyle(
                        color: user.email?.isNotEmpty == true ? headerTextColor : ObsidianUITheme.getSecondaryTextColor(context),
                        fontStyle: user.email?.isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ),
                  DataCell(Text(teamDisplay)),
                  DataCell(_buildRoleBadge(user.role)),
                  DataCell(Text(createdDisplay ?? '—')),
                  DataCell(Text(lastLoginDisplay)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canEdit) ...[
                          IconButton(
                            icon: Icon(Icons.edit_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                            tooltip: 'Edit User',
                            onPressed: () => _openEditModal(user),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                            tooltip: 'Delete User',
                            onPressed: () => _handleDeleteUser(user),
                          ),
                        ] else ...[
                          const SizedBox(width: 32),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    final caller = widget.apiService.currentUser;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final user = _users[index];
          final canEdit = _isSuperAdmin || (!user.isSuperAdmin && user.teamNumber == caller?.teamNumber);
          final teamDisplay = _isSuperAdmin ? '[${user.program}] Team ${user.teamNumber}' : 'Team ${user.teamNumber}';
          final lastLoginDisplay = _formatDate(user.lastLogin) ?? 'Never';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ObsidianGlassCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ObsidianUserAvatar(
                          profilePicture: user.profilePicture,
                          username: user.username,
                          size: 44,
                          serverUrl: widget.apiService.serverUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.username,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: ObsidianUITheme.getPrimaryTextColor(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user.email?.isNotEmpty == true ? user.email! : 'No email configured',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: ObsidianUITheme.getSecondaryTextColor(context),
                                  fontStyle: user.email?.isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildRoleBadge(user.role),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: ObsidianUITheme.getSecondaryTextColor(context)),
                        const SizedBox(width: 4),
                        Text(teamDisplay, style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                        const Spacer(),
                        Icon(Icons.access_time_rounded, size: 14, color: ObsidianUITheme.getSecondaryTextColor(context)),
                        const SizedBox(width: 4),
                        Text('Login: $lastLoginDisplay', style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context))),
                      ],
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: ObsidianUITheme.primaryAccent,
                              side: BorderSide(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4)),
                            ),
                            icon: const Icon(Icons.edit_rounded, size: 14),
                            label: Text(context.tr('users.edit', 'Edit')),
                            onPressed: () => _openEditModal(user),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: Colors.redAccent,
                              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded, size: 14),
                            label: Text(context.tr('users.delete', 'Delete')),
                            onPressed: () => _handleDeleteUser(user),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
        childCount: _users.length,
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    final r = role.toUpperCase();
    Color bg;
    Color fg;
    String label;

    switch (r) {
      case 'SUPERADMIN':
        bg = Colors.purple.withValues(alpha: 0.2);
        fg = Colors.purpleAccent;
        label = 'Site Admin';
        break;
      case 'ADMIN':
        bg = Colors.red.withValues(alpha: 0.2);
        fg = Colors.redAccent;
        label = 'Admin';
        break;
      case 'ANALYTICS':
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber;
        label = 'Analytics';
        break;
      case 'SCOUT':
      default:
        bg = Colors.cyan.withValues(alpha: 0.2);
        fg = Colors.cyanAccent;
        label = 'Scout';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  String? _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final dt = DateTime.parse(raw).toLocal();
      final year = dt.year.toString();
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$year-$month-$day $hour:$minute';
    } catch (_) {
      return raw;
    }
  }
}
