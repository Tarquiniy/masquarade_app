class ProfileModel {
  final String id;
  final String characterName;
  final String sect;
  final String clan;
  final int? humanity;
  final int generation;
  final List<String> disciplines;
  final int bloodPower;
  final int hunger;
  final List<int> domainIds;
  final String role;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? external_name;
  final int adminInfluence;
  final List<Map<String, dynamic>> pillars;
  final String? telegramChatId;
  ProfileModel( {
    required this.id,
    required this.characterName,
    required this.sect,
    required this.clan,
    required this.humanity,
    required this.generation,
    required this.disciplines,
    required this.bloodPower,
    required this.hunger,
    required this.domainIds,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.external_name,
    this.adminInfluence = 0,
    required this.pillars,
    this.telegramChatId,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    // Расчет человечности на основе столпов
    int humanity = json['pillars']?.length ?? 0;

    // Получаем дисциплины из JSON
  List<String> disciplines = List<String>.from(json['disciplines'] ?? []);

  // Добавляем обязательные дисциплины, если их еще нет
  final mandatoryDisciplines = ['Регенерация', 'Прочее'];
  for (var discipline in mandatoryDisciplines) {
    if (!disciplines.contains(discipline)) {
      disciplines.add(discipline);
    }
  }

    return ProfileModel(
      id: json['id'] ?? '',
      characterName: json['character_name'] ?? 'Безымянный',
      sect: json['sect'] ?? 'Неизвестно',
      clan: json['clan'] ?? 'Неизвестно',
      humanity: humanity,      // Значение по умолчанию
      disciplines: disciplines,
      bloodPower: json['blood_power'] ?? 0,
      hunger: json['hunger'] ?? 0,
      generation: json['generation'] ?? 13,
      domainIds: List<int>.from(json['domain_ids'] ?? []), 
      role: json['role'] ?? 'user',
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] ?? DateTime.now().toIso8601String(),
      ),
      external_name: json['external_name'],
      adminInfluence: (json['admin_influence'] as num?)?.toInt() ?? 0,
      pillars: List<Map<String, dynamic>>.from(
        json['pillars'] ?? [],
      ),
      telegramChatId: json['telegram_chat_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'character_name': characterName,
      'sect': sect,
      'clan': clan,
      'humanity': humanity,     
      'disciplines': disciplines,
      'blood_power': bloodPower,
      'hunger': hunger,
      'generation': generation, 
      'domain_ids': domainIds, 
      'role': role,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'external_name': external_name,
      'admin_influence': adminInfluence,
      'pillars': pillars,
      'telegram_chat_id': telegramChatId,
    };
  }

  bool get isDomainOwner => domainIds.isNotEmpty;
  bool get isAdmin => role == 'admin';
  bool get isStoryteller => role == 'storyteller';
  bool get isHungry => hunger > 0;

  ProfileModel copyWith({
  String? id,
  String? characterName,
  String? sect,
  String? clan,
  int? humanity,
  List<String>? disciplines,
  int? bloodPower,
  int? hunger,
  int? generation,
  List<int>? domainIds,
  String? role,
  DateTime? createdAt,
  DateTime? updatedAt,
  List<Map<String, dynamic>>? pillars,
  int? adminInfluence
}) {
  return ProfileModel(
    id: id ?? this.id,
    characterName: characterName ?? this.characterName,
    sect: sect ?? this.sect,
    clan: clan ?? this.clan,
    humanity: humanity ?? this.humanity, 
    disciplines: disciplines ?? List.from(this.disciplines),
    bloodPower: bloodPower ?? this.bloodPower,
    hunger: hunger ?? this.hunger,
    generation: generation ?? this.generation,
    domainIds: domainIds ?? List.from(this.domainIds),
    role: role ?? this.role,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pillars: pillars ?? List.from(this.pillars),
    telegramChatId: telegramChatId ?? this.telegramChatId,
  );
}
}