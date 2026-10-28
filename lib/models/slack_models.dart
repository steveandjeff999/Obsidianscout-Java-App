/// Slack integration models, matching the server's /api/slack payloads (SlackModels.kt).
library;

List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

/// A Slack message shown as a popup banner.
class SlackBanner {
  final String id;
  final String channel;
  final String author;
  final String text;
  final String url;
  final bool mentioned;
  final DateTime? createdAt;

  const SlackBanner({
    required this.id,
    required this.channel,
    required this.author,
    required this.text,
    required this.url,
    required this.mentioned,
    this.createdAt,
  });

  factory SlackBanner.fromJson(Map<String, dynamic> json) => SlackBanner(
        id: json['id']?.toString() ?? '',
        channel: json['channel']?.toString() ?? '#slack',
        author: json['author']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        mentioned: json['mentioned'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );

  /// Only https links into Slack are opened.
  Uri? get safeUri {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    return (host == 'slack.com' || host.endsWith('.slack.com')) ? uri : null;
  }
}

class SlackAudience {
  final bool everyone;
  final List<String> roles;
  final List<String> userIds;

  const SlackAudience({this.everyone = true, this.roles = const [], this.userIds = const []});

  factory SlackAudience.fromJson(Map<String, dynamic>? json) => SlackAudience(
        everyone: json?['everyone'] != false,
        roles: _strings(json?['roles']),
        userIds: _strings(json?['userIds']),
      );

  Map<String, dynamic> toJson() => {'everyone': everyone, 'roles': roles, 'userIds': userIds};

  SlackAudience copyWith({bool? everyone, List<String>? roles, List<String>? userIds}) => SlackAudience(
        everyone: everyone ?? this.everyone,
        roles: roles ?? this.roles,
        userIds: userIds ?? this.userIds,
      );
}

/// One watched channel and what in it raises a banner for whom.
class SlackChannelRule {
  final String channelId;
  final String channelName;
  final bool isPrivate;
  /// "MENTIONS" or "ALL_MESSAGES".
  final String trigger;
  final bool mentionChannel;
  final List<String> userGroupIds;
  final bool mentionLinkedUsers;
  final List<String> keywords;
  final bool includeThreadReplies;
  final SlackAudience audience;
  final bool push;

  const SlackChannelRule({
    required this.channelId,
    this.channelName = '',
    this.isPrivate = false,
    this.trigger = 'MENTIONS',
    this.mentionChannel = true,
    this.userGroupIds = const [],
    this.mentionLinkedUsers = true,
    this.keywords = const [],
    this.includeThreadReplies = false,
    this.audience = const SlackAudience(),
    this.push = false,
  });

  factory SlackChannelRule.fromJson(Map<String, dynamic> json) => SlackChannelRule(
        channelId: json['channelId']?.toString() ?? '',
        channelName: json['channelName']?.toString() ?? '',
        isPrivate: json['isPrivate'] == true,
        trigger: json['trigger']?.toString() ?? 'MENTIONS',
        mentionChannel: json['mentionChannel'] != false,
        userGroupIds: _strings(json['userGroupIds']),
        mentionLinkedUsers: json['mentionLinkedUsers'] != false,
        keywords: _strings(json['keywords']),
        includeThreadReplies: json['includeThreadReplies'] == true,
        audience: SlackAudience.fromJson(json['audience'] as Map<String, dynamic>?),
        push: json['push'] == true,
      );

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'channelName': channelName,
        'isPrivate': isPrivate,
        'trigger': trigger,
        'mentionChannel': mentionChannel,
        'userGroupIds': userGroupIds,
        'mentionLinkedUsers': mentionLinkedUsers,
        'keywords': keywords,
        'includeThreadReplies': includeThreadReplies,
        'audience': audience.toJson(),
        'push': push,
      };

  SlackChannelRule copyWith({
    String? channelName,
    bool? isPrivate,
    String? trigger,
    bool? mentionChannel,
    List<String>? userGroupIds,
    bool? mentionLinkedUsers,
    List<String>? keywords,
    bool? includeThreadReplies,
    SlackAudience? audience,
    bool? push,
  }) =>
      SlackChannelRule(
        channelId: channelId,
        channelName: channelName ?? this.channelName,
        isPrivate: isPrivate ?? this.isPrivate,
        trigger: trigger ?? this.trigger,
        mentionChannel: mentionChannel ?? this.mentionChannel,
        userGroupIds: userGroupIds ?? this.userGroupIds,
        mentionLinkedUsers: mentionLinkedUsers ?? this.mentionLinkedUsers,
        keywords: keywords ?? this.keywords,
        includeThreadReplies: includeThreadReplies ?? this.includeThreadReplies,
        audience: audience ?? this.audience,
        push: push ?? this.push,
      );
}

class SlackIntegration {
  final bool configured;
  final bool enabled;
  final bool botTokenSet;
  final bool appTokenSet;
  final String workspaceName;
  final String status;
  final String statusDetail;
  final DateTime? lastEventAt;
  final List<SlackChannelRule> rules;
  final Map<String, String> userLinks;
  final String manifestUrl;

  const SlackIntegration({
    this.configured = false,
    this.enabled = false,
    this.botTokenSet = false,
    this.appTokenSet = false,
    this.workspaceName = '',
    this.status = 'disconnected',
    this.statusDetail = '',
    this.lastEventAt,
    this.rules = const [],
    this.userLinks = const {},
    this.manifestUrl = '',
  });

  factory SlackIntegration.fromJson(Map<String, dynamic> json) => SlackIntegration(
        configured: json['configured'] == true,
        enabled: json['enabled'] == true,
        botTokenSet: json['botTokenSet'] == true,
        appTokenSet: json['appTokenSet'] == true,
        workspaceName: json['workspaceName']?.toString() ?? '',
        status: json['status']?.toString() ?? 'disconnected',
        statusDetail: json['statusDetail']?.toString() ?? '',
        lastEventAt: DateTime.tryParse(json['lastEventAt']?.toString() ?? ''),
        rules: (json['rules'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SlackChannelRule.fromJson)
            .toList(),
        userLinks: (json['userLinks'] as Map? ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        manifestUrl: json['manifestUrl']?.toString() ?? '',
      );
}

class SlackChannel {
  final String id;
  final String name;
  final bool isPrivate;
  final bool isMember;
  final int memberCount;

  const SlackChannel({required this.id, required this.name, this.isPrivate = false, this.isMember = false, this.memberCount = 0});

  factory SlackChannel.fromJson(Map<String, dynamic> json) => SlackChannel(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        isPrivate: json['isPrivate'] == true,
        isMember: json['isMember'] == true,
        memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      );
}

class SlackUserGroup {
  final String id;
  final String handle;
  final String name;

  const SlackUserGroup({required this.id, required this.handle, required this.name});

  factory SlackUserGroup.fromJson(Map<String, dynamic> json) => SlackUserGroup(
        id: json['id']?.toString() ?? '',
        handle: json['handle']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

/// A team member and the Slack account they are linked to.
class SlackLinkedMember {
  final String userId;
  final String username;
  final String role;
  final String autoSlackUserId;

  const SlackLinkedMember({required this.userId, required this.username, required this.role, required this.autoSlackUserId});

  factory SlackLinkedMember.fromJson(Map<String, dynamic> json) => SlackLinkedMember(
        userId: json['userId']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        autoSlackUserId: json['autoSlackUserId']?.toString() ?? '',
      );
}

class SlackPerson {
  final String id;
  final String name;
  final String realName;

  const SlackPerson({required this.id, required this.name, required this.realName});

  factory SlackPerson.fromJson(Map<String, dynamic> json) => SlackPerson(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        realName: json['realName']?.toString() ?? '',
      );

  String get label => realName.isNotEmpty && realName != name ? '$name ($realName)' : name;
}
