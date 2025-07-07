class ProfileModel {
  final String id;
  final String characterName;
  final String sect;
  final String clan;
  final String status;
  final List<String> disciplines;
  final int bloodPower;
  final int hunger;
  final int influence;
  final String? domain;
  final String role;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? external_name;

  ProfileModel({
    required this.id,
    required this.characterName,
    required this.sect,
    required this.clan,
    required this.status,
    required this.disciplines,
    required this.bloodPower,
    required this.hunger,
    required this.influence,
    required this.domain,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.external_name,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] ?? '',
      characterName: json['character_name'] ?? 'Безымянный',
      sect: json['sect'] ?? 'Неизвестно',
      clan: json['clan'] ?? 'Неизвестно',
      status: json['status'] ?? 'Новичок',
      disciplines: List<String>.from(json['disciplines'] ?? []),
      bloodPower: json['blood_power'] ?? 0,
      hunger: json['hunger'] ?? 0,
      influence: json['influence'] ?? 0,
      domain: json['domain'],
      role: json['role'] ?? 'user',
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] ?? DateTime.now().toIso8601String(),
      ),
      external_name: json['external_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'character_name': characterName,
      'sect': sect,
      'clan': clan,
      'status': status,
      'disciplines': disciplines,
      'blood_power': bloodPower,
      'hunger': hunger,
      'influence': influence,
      'domain': domain,
      'role': role,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'telegram_username': external_name,
    };
  }

  bool get isDomainOwner => domain != null && domain!.isNotEmpty;
  bool get isAdmin => role == 'admin';
  bool get isStoryteller => role == 'storyteller';
  bool get isHungry => hunger > 0;

  ProfileModel copyWith({
    String? id,
    String? characterName,
    String? sect,
    String? clan,
    String? status,
    List<String>? disciplines,
    int? bloodPower,
    int? hunger,
    int? influence,
    String? domain,
    String? role,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? telegramUsername,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      characterName: characterName ?? this.characterName,
      sect: sect ?? this.sect,
      clan: clan ?? this.clan,
      status: status ?? this.status,
      disciplines: disciplines ?? this.disciplines,
      bloodPower: bloodPower ?? this.bloodPower,
      hunger: hunger ?? this.hunger,
      influence: influence ?? this.influence,
      domain: domain ?? this.domain,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      external_name: external_name ?? this.external_name,
    );
  }
}
