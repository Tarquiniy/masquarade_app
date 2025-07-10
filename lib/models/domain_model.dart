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

    return DomainModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id'].toString()) ?? -1,
      name: json['name'] as String? ?? 'Без названия',
      ownerId: json['ownerId']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      boundaryPoints: parseBoundaryPoints(json['boundaryPoints']),
      securityLevel: (json['securityLevel'] as num?)?.toInt() ?? 0,
      influenceLevel: (json['influenceLevel'] as num?)?.toInt() ?? 0,
      income: (json['income'] as num?)?.toInt() ?? 0,
      isNeutral: json['isNeutral'] as bool? ?? false,
      openViolationsCount:
          (json['open_violations_count'] as num?)?.toInt() ?? 0,
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
      if (isNeutral) return true;

      if (boundaryPoints.isEmpty) return false;

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
