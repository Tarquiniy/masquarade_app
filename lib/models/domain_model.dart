import 'dart:convert';

import 'package:latlong2/latlong.dart';

class DomainModel {
  final int id;
  final String name;
  final String ownerId;
  final double latitude;
  final double longitude;
  final List<LatLng> boundaryPoints;
  final int securityLevel;
  final int influenceLevel;
  final int income;
  final bool isNeutral;
  final int openViolationsCount;

  DomainModel({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.latitude,
    required this.longitude,
    required this.boundaryPoints,
    this.securityLevel = 0,
    this.influenceLevel = 0,
    this.income = 0,
    this.isNeutral = false,
    this.openViolationsCount = 0,
  });

  factory DomainModel.fromJson(Map<String, dynamic> json) {
    return DomainModel(
      id: json['id'] as int,
      name: json['name'] as String,
      ownerId: json['ownerId'],
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      boundaryPoints: (() {
        final raw = json['boundaryPoints'];
        if (raw is String) {
          final list = jsonDecode(raw);
          return List<LatLng>.from(list.map((e) => LatLng(e['lat'], e['lng'])));
        } else if (raw is List) {
          return List<LatLng>.from(raw.map((e) => LatLng(e['lat'], e['lng'])));
        } else {
          return <LatLng>[];
        }
      })(),
      securityLevel: json['securityLevel'] ?? 0,
      influenceLevel: json['influenceLevel'] ?? 0,
      income: json['income'] ?? 0,
      isNeutral: json['isNeutral'] ?? false,
      openViolationsCount: json['open_violations_count'] ?? 0,
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
      'influenceLevel': influenceLevel,
      'income': income,
      'isNeutral': isNeutral,
      'open_violations_count': openViolationsCount,
    };
  }

  bool isPointInside(double lat, double lng) {
    try {
      // Нейтральная территория везде
      if (isNeutral) return true;

      // Упрощенная проверка для обычных доменов
      final distance = Distance();
      final center = LatLng(latitude, longitude);
      final point = LatLng(lat, lng);

      return distance(center, point) < 1000;
    } catch (e) {
      print('Ошибка проверки точки в домене: $e');
      return false;
    }
  }
}
