part of 'masquerade_bloc.dart';

abstract class MasqueradeEvent extends Equatable {
  const MasqueradeEvent();

  @override
  List<Object?> get props => [];
}

class LoadViolations extends MasqueradeEvent {}

class ReportViolation extends MasqueradeEvent {
  final String description;
  final int hungerSpent;
  final double latitude;
  final double longitude;
  final int domainId; // ← исправлено

  const ReportViolation({
    required this.description,
    required this.hungerSpent,
    required this.latitude,
    required this.longitude,
    required this.domainId,
  });

  @override
  List<Object?> get props => [
    description,
    hungerSpent,
    latitude,
    longitude,
    domainId,
  ];
}

class StartHunt extends MasqueradeEvent {
  final bool isDomainOwner;
  final Position position;
  final int domainId; // ← исправлено

  const StartHunt({
    required this.isDomainOwner,
    required this.position,
    required this.domainId,
  });

  @override
  List<Object?> get props => [isDomainOwner, position, domainId];
}

class CloseViolation extends MasqueradeEvent {
  final String violationId;

  const CloseViolation(this.violationId);

  @override
  List<Object?> get props => [violationId];
}

class RevealViolator extends MasqueradeEvent {
  final String violationId;

  const RevealViolator(this.violationId);

  @override
  List<Object?> get props => [violationId];
}
