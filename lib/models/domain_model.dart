import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';

class DomainModel {
  final int id;
  final String name;
  final String ownerId;
  final double latitude;
  final double longitude;
  final List<LatLng> boundaryPoints;
  final int securityLevel;
  final int maxSecurityLevel;
  late final int influenceLevel;
  final int maxinfluenceLevel;
  final int income;
  final int baseIncome;
  final bool isNeutral;
  final int openViolationsCount;
  final int adminInfluence;


  DomainModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.latitude,
    required this.longitude,
    required this.boundaryPoints,
    this.securityLevel = 0,
    this.maxSecurityLevel = 10,
    this.influenceLevel = 0,
    this.maxinfluenceLevel = 10,
    this.income = 0,
    this.baseIncome = 0,
    this.isNeutral = false,
    this.openViolationsCount = 0,
    this.adminInfluence = 0,
  });

  factory DomainModel.fromJson(Map<String, dynamic> json) {
    List<LatLng> parseBoundaryPoints(dynamic raw) {
      try {
        if (raw is String) {
          final list = jsonDecode(raw) as List;
          return list.map((e) {
            return LatLng(
              double.parse(e['lat'].toString()),
              double.parse(e['lng'].toString()),
            );
          }).toList();
        } else if (raw is List) {
          return raw.map((e) {
            return LatLng(
              double.parse(e['lat'].toString()),
              double.parse(e['lng'].toString()),
            );
          }).toList();
        }
      } catch (e) {
        print('Error parsing boundary points: $e');
      }
      return [];
    }

    // Парсим время последней проверки штрафов
    DateTime? lastPenaltyCheck;
    if (json['last_penalty_check'] != null) {
      lastPenaltyCheck = DateTime.tryParse(json['last_penalty_check']);
    }

    final isNeutral = json['isNeutral'] as bool? ?? false;
    final ownerId = json['ownerId']?.toString() ?? '';
    final securityLevel = (json['securityLevel'] as num?)?.toInt() ?? 0;
    final maxSecurityLevel = (json['max_security_level'] as num?)?.toInt() ?? 10; // Получаем из JSON
    final maxinfluenceLevel = (json['max_influence_level'] as num?)?.toInt() ?? 10; // Получаем из JSON
    final influenceLevel = (json['influenceLevel'] as num?)?.toInt() ?? 0;
    final baseIncome = (json['base_income'] as num?)?.toInt() ?? 
                      (json['baseIncome'] as num?)?.toInt() ?? 0;

    return DomainModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? -1,
      name: json['name'] as String? ?? 'Без названия',
      ownerId: isNeutral ? '' : ownerId,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      boundaryPoints: parseBoundaryPoints(json['boundaryPoints']),
      securityLevel: securityLevel,
      maxSecurityLevel: maxSecurityLevel, // Используем полученное значение
      influenceLevel: (json['influenceLevel'] as num?)?.toInt() ?? 0,
      maxinfluenceLevel: maxinfluenceLevel,
      income: (json['income'] as num?)?.toInt() ?? 0,
      isNeutral: isNeutral,
      baseIncome: baseIncome, // Используем исправленное значение
      openViolationsCount: (json['open_violations_count'] as num?)?.toInt() ?? 0,
      adminInfluence: (json['admin_influence'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ownerId': ownerId,
      'latitude': latitude,
      'longitude': longitude,
      'boundaryPoints': boundaryPoints
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
      'securityLevel': securityLevel,
      'max_security_level': maxSecurityLevel,
      'influenceLevel': influenceLevel,
      'max_influence_level': maxinfluenceLevel,
      'income': income,
      'baseIncome': baseIncome, // Сохраняем в camelCase для совместимости
      'base_income': baseIncome, // И в snake_case для Supabase
      'isNeutral': isNeutral,
      'open_violations_count': openViolationsCount,
      'admin_influence': adminInfluence,
    };
  }

  // Обновляем метод copyWith
  DomainModel copyWith({
    int? id,
    String? name,
    String? ownerId,
    double? latitude,
    double? longitude,
    List<LatLng>? boundaryPoints,
    int? securityLevel,
    int? maxSecurityLevel,
    int? influenceLevel,
    int? maxinfluenceLevel,
    int? income,
    int? baseIncome,
    bool? isNeutral,
    int? openViolationsCount,
    int? adminInfluence,
  }) {
    return DomainModel(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      boundaryPoints: boundaryPoints ?? this.boundaryPoints,
      securityLevel: securityLevel ?? this.securityLevel,
      maxSecurityLevel: maxSecurityLevel ?? this.maxSecurityLevel,
      influenceLevel: influenceLevel ?? this.influenceLevel,
      maxinfluenceLevel: maxinfluenceLevel ?? this.maxinfluenceLevel,
      income: income ?? this.income,
      baseIncome: baseIncome ?? this.baseIncome,
      isNeutral: isNeutral ?? this.isNeutral,
      openViolationsCount: openViolationsCount ?? this.openViolationsCount,
      adminInfluence: adminInfluence ?? this.adminInfluence,
    );
  }

  bool isPointInside(double lat, double lng) {
  {
    if (isNeutral) {
      // Для нейтральных доменов используем упрощенную проверку
      final distance = Distance();
      final centerDistance = distance(LatLng(latitude, longitude), LatLng(lat, lng));
      return centerDistance <= 2000; // 2 км радиус для нейтральных территорий
    }

    if (boundaryPoints.isEmpty) return false;

    final point = LatLng(lat, lng);
    final distance = Distance();

    // Проверка расстояния до центра
    final centerDistance = distance(LatLng(latitude, longitude), point);
    if (centerDistance > 2000) return false;

    // Проверка принадлежности к полигону
    bool isInside = false;
    var j = boundaryPoints.length - 1;

    for (int i = 0; i < boundaryPoints.length; i++) {
      final p1 = boundaryPoints[i];
      final p2 = boundaryPoints[j];

      if (p1.longitude < point.longitude && p2.longitude >= point.longitude ||
          p2.longitude < point.longitude && p1.longitude >= point.longitude) {
        if (p1.latitude +
                (point.longitude - p1.longitude) /
                    (p2.longitude - p1.longitude) *
                    (p2.latitude - p1.latitude) <
            point.latitude) {
          isInside = !isInside;
        }
      }
      j = i;
    }

    return isInside;
  }
}
}