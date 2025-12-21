// lib/models/message.dart

class Message {
  final String? id;
  final String senderId;
  final String? receiverId;
  final MessageType messageType;
  final String content;
  final String? response;
  final DateTime timestamp;
  final bool isAnswered;
  final bool isSynced;
  // NEW FIELDS
  final bool isDeleted;
  final DateTime? deletedAt;
  final bool isEdited;
  final DateTime? editedAt;
  final String? originalContent;
  final List<String> readBy;
  final String? conversationId;
  final String? answeredBy;
  final DateTime? answeredAt;
  // For broadcast messages
  final List<String>? targetRoles;
  final String? targetSurveyId;
  final List<String>? targetUserIds;
  // Enriched data
  final Map<String, dynamic>? sender;
  final Map<String, dynamic>? receiver;

  Message({
    this.id,
    required this.senderId,
    this.receiverId,
    required this.messageType,
    required this.content,
    this.response,
    required this.timestamp,
    this.isAnswered = false,
    this.isSynced = false,
    this.isDeleted = false,
    this.deletedAt,
    this.isEdited = false,
    this.editedAt,
    this.originalContent,
    this.readBy = const [],
    this.conversationId,
    this.answeredBy,
    this.answeredAt,
    this.targetRoles,
    this.targetSurveyId,
    this.targetUserIds,
    this.sender,
    this.receiver,
  });

  Message copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    MessageType? messageType,
    String? content,
    String? response,
    DateTime? timestamp,
    bool? isAnswered,
    bool? isSynced,
    bool? isDeleted,
    DateTime? deletedAt,
    bool? isEdited,
    DateTime? editedAt,
    String? originalContent,
    List<String>? readBy,
    String? conversationId,
    String? answeredBy,
    DateTime? answeredAt,
    List<String>? targetRoles,
    String? targetSurveyId,
    List<String>? targetUserIds,
    Map<String, dynamic>? sender,
    Map<String, dynamic>? receiver,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      response: response ?? this.response,
      timestamp: timestamp ?? this.timestamp,
      isAnswered: isAnswered ?? this.isAnswered,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      originalContent: originalContent ?? this.originalContent,
      readBy: readBy ?? this.readBy,
      conversationId: conversationId ?? this.conversationId,
      answeredBy: answeredBy ?? this.answeredBy,
      answeredAt: answeredAt ?? this.answeredAt,
      targetRoles: targetRoles ?? this.targetRoles,
      targetSurveyId: targetSurveyId ?? this.targetSurveyId,
      targetUserIds: targetUserIds ?? this.targetUserIds,
      sender: sender ?? this.sender,
      receiver: receiver ?? this.receiver,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      senderId: json['sender_id'],
      receiverId: json['receiver_id'],
      messageType: MessageType.values.firstWhere(
            (e) => e.name == json['message_type'],
        orElse: () => MessageType.ai,
      ),
      content: json['content'],
      response: json['response'],
      timestamp: DateTime.parse(json['timestamp']),
      isAnswered: json['answered'] ?? false,
      isSynced: json['is_synced'] ?? true,
      isDeleted: json['is_deleted'] ?? false,
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at']) : null,
      isEdited: json['is_edited'] ?? false,
      editedAt: json['edited_at'] != null ? DateTime.parse(json['edited_at']) : null,
      originalContent: json['original_content'],
      readBy: json['read_by'] != null ? List<String>.from(json['read_by']) : [],
      conversationId: json['conversation_id'],
      answeredBy: json['answered_by'],
      answeredAt: json['answered_at'] != null ? DateTime.parse(json['answered_at']) : null,
      targetRoles: json['target_roles'] != null ? List<String>.from(json['target_roles']) : null,
      targetSurveyId: json['target_survey_id'],
      targetUserIds: json['target_user_ids'] != null ? List<String>.from(json['target_user_ids']) : null,
      sender: json['sender'],
      receiver: json['receiver'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_type': messageType.name,
      'content': content,
      'response': response,
      'timestamp': timestamp.toIso8601String(),
      'answered': isAnswered,
      'is_synced': isSynced,
      'is_deleted': isDeleted,
      if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
      'is_edited': isEdited,
      if (editedAt != null) 'edited_at': editedAt!.toIso8601String(),
      'original_content': originalContent,
      'read_by': readBy,
      'conversation_id': conversationId,
      'answered_by': answeredBy,
      if (answeredAt != null) 'answered_at': answeredAt!.toIso8601String(),
      if (targetRoles != null) 'target_roles': targetRoles,
      if (targetSurveyId != null) 'target_survey_id': targetSurveyId,
      if (targetUserIds != null) 'target_user_ids': targetUserIds,
    };
  }

  /// Check if current user has read this message
  bool isReadBy(String userId) => readBy.contains(userId);

  /// Check if message is from current user
  bool isFromUser(String userId) => senderId == userId;

  /// Get display name for sender
  String getSenderName() {
    if (sender != null) {
      return sender!['username'] ?? sender!['email'] ?? 'Unknown';
    }
    return 'Unknown';
  }
}

enum MessageType {
  ai,
  supervisor,
  broadcast  // NEW: For admin broadcast messages
}

/// Model for conversation list (supervisor view)
class ConversationPreview {
  final Map<String, dynamic> enumerator;
  final Message? latestMessage;
  final int unreadCount;
  final int unansweredCount;

  ConversationPreview({
    required this.enumerator,
    this.latestMessage,
    this.unreadCount = 0,
    this.unansweredCount = 0,
  });

  factory ConversationPreview.fromJson(Map<String, dynamic> json) {
    return ConversationPreview(
      enumerator: json['enumerator'] ?? {},
      latestMessage: json['latest_message'] != null
          ? Message.fromJson(json['latest_message'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      unansweredCount: json['unanswered_count'] ?? 0,
    );
  }

  String get enumeratorName => enumerator['username'] ?? enumerator['email'] ?? 'Unknown';
  String get enumeratorId => enumerator['id'] ?? '';
}

/// Model for chat statistics (admin view)
class ChatStats {
  final int totalMessages;
  final int aiMessages;
  final int supervisorMessages;
  final int broadcastMessages;
  final int unansweredMessages;
  final List<DailyStat> dailyStats;

  ChatStats({
    required this.totalMessages,
    required this.aiMessages,
    required this.supervisorMessages,
    required this.broadcastMessages,
    required this.unansweredMessages,
    required this.dailyStats,
  });

  factory ChatStats.fromJson(Map<String, dynamic> json) {
    return ChatStats(
      totalMessages: json['total_messages'] ?? 0,
      aiMessages: json['ai_messages'] ?? 0,
      supervisorMessages: json['supervisor_messages'] ?? 0,
      broadcastMessages: json['broadcast_messages'] ?? 0,
      unansweredMessages: json['unanswered_messages'] ?? 0,
      dailyStats: (json['daily_stats'] as List?)
          ?.map((e) => DailyStat.fromJson(e))
          .toList() ?? [],
    );
  }
}

class DailyStat {
  final String date;
  final int count;

  DailyStat({required this.date, required this.count});

  factory DailyStat.fromJson(Map<String, dynamic> json) {
    return DailyStat(
      date: json['_id'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}