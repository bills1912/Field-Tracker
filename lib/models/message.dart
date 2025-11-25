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
  });

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
    };
  }
}

enum MessageType { ai, supervisor }