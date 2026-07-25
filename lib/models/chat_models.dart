class ChatMessageModel {
  final String id;
  final String userId;
  final String username;
  final String content;
  final String createdAt;
  final String? profilePicture;
  final Map<String, List<String>> reactions;

  ChatMessageModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.createdAt,
    this.profilePicture,
    required this.reactions,
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
