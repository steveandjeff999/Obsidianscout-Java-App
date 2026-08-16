class ChatMessageModel {
  final String id;
  final String userId;
  final String username;
  final String content;
  final String createdAt;
  final String? profilePicture;
  final Map<String, List<String>> reactions;
  final bool isEdited;
  final String? updatedAt;

  ChatMessageModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.createdAt,
    this.profilePicture,
    required this.reactions,
    this.isEdited = false,
    this.updatedAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'];
    final Map<String, List<String>> parsedReactions = {};

    if (rawReactions is Map) {
      rawReactions.forEach((key, val) {
        if (val is List) {
          parsedReactions[key.toString()] = val.map((e) => e.toString()).toList();
        }
      });
    }

    return ChatMessageModel(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? 'Anonymous',
      content: json['content']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
      profilePicture: json['profilePicture']?.toString(),
      reactions: parsedReactions,
      isEdited: json['isEdited'] == true,
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'username': username,
        'content': content,
        'createdAt': createdAt,
        'profilePicture': profilePicture,
        'reactions': reactions,
        'isEdited': isEdited,
        'updatedAt': updatedAt,
      };
}

class ChatGroupUnreadModel {
  final String groupName;
  final int unreadCount;
  final int mentionCount;

  ChatGroupUnreadModel({
    required this.groupName,
    required this.unreadCount,
    required this.mentionCount,
  });

  factory ChatGroupUnreadModel.fromJson(Map<String, dynamic> json) {
    return ChatGroupUnreadModel(
      groupName: json['groupName']?.toString() ?? '',
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      mentionCount: (json['mentionCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatGroupDetailsModel {
  final String groupName;
  final bool isDefault;
  final List<String> allowedRoles;
  final List<String> allowedUserIds;
  final String? createdByUserId;
  final String? createdAt;

  ChatGroupDetailsModel({
    required this.groupName,
    this.isDefault = false,
    required this.allowedRoles,
    required this.allowedUserIds,
    this.createdByUserId,
    this.createdAt,
  });

  factory ChatGroupDetailsModel.fromJson(Map<String, dynamic> json) {
    return ChatGroupDetailsModel(
      groupName: json['groupName']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
      allowedRoles: (json['allowedRoles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      allowedUserIds: (json['allowedUserIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      createdByUserId: json['createdByUserId']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'groupName': groupName,
        'isDefault': isDefault,
        'allowedRoles': allowedRoles,
        'allowedUserIds': allowedUserIds,
        'createdByUserId': createdByUserId,
        'createdAt': createdAt,
      };
}

class ChatTeamMemberModel {
  final String userId;
  final String username;
  final String role;
  final String? profilePicture;

  ChatTeamMemberModel({
    required this.userId,
    required this.username,
    required this.role,
    this.profilePicture,
  });

  factory ChatTeamMemberModel.fromJson(Map<String, dynamic> json) {
    return ChatTeamMemberModel(
      userId: json['userId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      profilePicture: json['profilePicture']?.toString(),
    );
  }
}

