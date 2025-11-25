class FAQ {
  final String id;
  final String question;
  final String answer;
  final String category;
  final DateTime createdAt;

  FAQ({
    required this.id,
    required this.question,
    required this.answer,
    required this.category,
    required this.createdAt,
  });

  factory FAQ.fromJson(Map<String, dynamic> json) {
    return FAQ(
      id: json['id'],
      question: json['question'],
      answer: json['answer'],
      category: json['category'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'answer': answer,
      'category': category,
      'created_at': createdAt.toIso8601String(),
    };
  }
}