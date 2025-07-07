import 'package:latlong2/latlong.dart';

enum ViolationStatus { open, closed, revealed }

class ViolationModel {
  final String id;
  final String violatorId;
  final String? violatorName;
  final int domainId; // ✅ теперь int
  final String description;
  final int hungerSpent;
  final int costToClose;
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
    return !isRevealed && !isClosed && now.difference(createdAt).inHours <= 24;
  }

  LatLng get position => LatLng(latitude, longitude);
}
