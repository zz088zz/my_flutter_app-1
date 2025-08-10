class Reward {
  final String? id;
  final String userId;
  final double points;
  final String description;
  final String type; // 'earned' or 'redeemed'
  final DateTime createdAt;

  Reward({
    this.id,
    required this.userId,
    required this.points,
    required this.description,
    required this.type,
    required this.createdAt,
  });

  factory Reward.fromMap(Map<String, dynamic> map) {
    DateTime createdAt;
    if (map['created_at'] is String) {
      createdAt = DateTime.parse(map['created_at']);
    } else {
      createdAt = DateTime.now();
    }

    return Reward(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      points: (map['points'] ?? 0).toDouble(),
      description: map['description'] ?? '',
      type: map['type'] ?? 'earned',
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'points': points,
      'description': description,
      'type': type,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isEarned => type == 'earned';
  bool get isRedeemed => type == 'redeemed';
}
