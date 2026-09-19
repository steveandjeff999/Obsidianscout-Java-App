import 'package:flutter/material.dart';

class DesktopTab {
  final String id;
  int screenIndex;
  final List<int> history;
  String? customTitle;
  IconData? customIcon;
  String? pendingChatChannel;
  final DateTime createdAt;

  DesktopTab({
    required this.id,
    required this.screenIndex,
    List<int>? history,
    this.customTitle,
    this.customIcon,
    this.pendingChatChannel,
    DateTime? createdAt,
  })  : history = history ?? [],
        createdAt = createdAt ?? DateTime.now();

  DesktopTab copyWith({
    String? id,
    int? screenIndex,
    List<int>? history,
    String? customTitle,
    IconData? customIcon,
    String? pendingChatChannel,
  }) {
    return DesktopTab(
      id: id ?? this.id,
      screenIndex: screenIndex ?? this.screenIndex,
      history: history != null ? List<int>.from(history) : List<int>.from(this.history),
      customTitle: customTitle ?? this.customTitle,
      customIcon: customIcon ?? this.customIcon,
      pendingChatChannel: pendingChatChannel ?? this.pendingChatChannel,
      createdAt: createdAt,
    );
  }
}
