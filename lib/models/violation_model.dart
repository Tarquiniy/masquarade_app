import 'package:latlong2/latlong.dart';

enum ViolationStatus { open, closed, revealed }

class ViolationModel {
  final String id;
  final String violatorId;
  final String? violatorName;
  final int domainId;
  final String description;
  final int hungerSpent;
  final int costToClose;
  final int costToReveal;
  final ViolationStatus status;
  final bool violatorKnown;
  final DateTime createdAt;
  final DateTime? closedAt;
  final DateTime? revealedAt;
  final double latitude;
  final double longitude;
  final String? resolvedBy;

  ViolationModel({
    required this.id,
    required this.violatorId,
    required this.violatorName,
    required this.domainId,
    required this.description,
    required this.hungerSpent,
    required this.costToClose,
    required this.costToReveal,
    required this.status,
    required this.violatorKnown,
    required this.createdAt,
    required this.latitude,
    required this.longitude,
    this.closedAt,
    this.revealedAt,
    this.resolvedBy,
  });

  factory ViolationModel.fromJson(Map<String, dynamic> json) {
    try {
      return ViolationModel(
        id: json['id'] as String,
        violatorId: json['violator_id'] as String,
        violatorName: json['violator_name'],
        domainId: json['domain_id'] as int,
        description: json['description'] as String,
        hungerSpent: json['hunger_spent'] ?? 0,
        costToClose: json['cost_to_close'] ?? 0,
        costToReveal: json['cost_to_reveal'] ?? 0,
        status: _statusFromString(json['status']),
        violatorKnown: json['violator_known'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
        closedAt: json['closed_at'] != null
            ? DateTime.tryParse(json['closed_at'])
            : null,
        revealedAt: json['revealed_at'] != null
            ? DateTime.tryParse(json['revealed_at'])
            : null,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        resolvedBy: json['resolved_by'],
      );
    } catch (e, stack) {
      print('❌ Ошибка в ViolationModel.fromJson: $e\n$stack');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'violator_id': violatorId,
      'violator_name': violatorName,
      'domain_id': domainId,
      'description': description,
      'hunger_spent': hungerSpent,
      'cost_to_close': costToClose,
      'cost_to_reveal': costToReveal,
      'status': _statusToString(status),
      'violator_known': violatorKnown,
      'created_at': createdAt.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'revealed_at': revealedAt?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'resolved_by': resolvedBy,
    };
  }

  ViolationModel copyWith({
    String? id,
    String? violatorId,
    String? violatorName,
    int? domainId,
    String? description,
    int? hungerSpent,
    int? costToClose,
    int? costToReveal,
    ViolationStatus? status,
    bool? violatorKnown,
    DateTime? createdAt,
    DateTime? closedAt,
    DateTime? revealedAt,
    double? latitude,
    double? longitude,
    String? resolvedBy,
  }) {
    return ViolationModel(
      id: id ?? this.id,
      violatorId: violatorId ?? this.violatorId,
      violatorName: violatorName ?? this.violatorName,
      domainId: domainId ?? this.domainId,
      description: description ?? this.description,
      hungerSpent: hungerSpent ?? this.hungerSpent,
      costToClose: costToClose ?? this.costToClose,
      costToReveal: costToReveal ?? this.costToReveal,
      status: status ?? this.status,
      violatorKnown: violatorKnown ?? this.violatorKnown,
      createdAt: createdAt ?? this.createdAt,
      closedAt: closedAt ?? this.closedAt,
      revealedAt: revealedAt ?? this.revealedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      resolvedBy: resolvedBy ?? this.resolvedBy,
    );
  }

  static ViolationStatus _statusFromString(String value) {
    switch (value) {
      case 'closed':
        return ViolationStatus.closed;
      case 'revealed':
        return ViolationStatus.revealed;
      default:
        return ViolationStatus.open;
    }
  }

  static String _statusToString(ViolationStatus status) {
    switch (status) {
      case ViolationStatus.closed:
        return 'closed';
      case ViolationStatus.revealed:
        return 'revealed';
      default:
        return 'open';
    }
  }

  bool get isClosed => status == ViolationStatus.closed;
  bool get isRevealed => status == ViolationStatus.revealed;
  bool get canBeRevealed {
    final now = DateTime.now();
    // Добавляем проверку, что нарушение еще не было раскрыто или закрыто
    return !isRevealed && !isClosed && now.difference(createdAt).inHours <= 24;
  }

  // Добавляем новый геттер для проверки возможности закрытия
  bool get canBeClosed {
    // Закрыть можно только открытые нарушения
    return status == ViolationStatus.open;
  }

  LatLng get position => LatLng(latitude, longitude);
}
