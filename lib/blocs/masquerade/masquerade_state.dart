part of 'masquerade_bloc.dart';

abstract class MasqueradeState extends Equatable {
  const MasqueradeState();

  @override
  List<Object?> get props => [];
}

class ViolationsLoading extends MasqueradeState {}

class ViolationsLoaded extends MasqueradeState {
  final List<ViolationModel> violations;

  const ViolationsLoaded(this.violations);

  @override
  List<Object?> get props => [violations];
}

class ViolationsError extends MasqueradeState {
  final String message;

  const ViolationsError(this.message);

  @override
  List<Object?> get props => [message];
}

class ViolationReportedSuccessfully extends MasqueradeState {}

class ViolationClosedSuccessfully extends MasqueradeState {}

class ViolatorRevealedSuccessfully extends MasqueradeState {}

class HuntCompleted extends MasqueradeState {
  final bool violationOccurred;
  final bool isDomainOwner;
  final int costToClose;

  const HuntCompleted({
    required this.violationOccurred,
    required this.isDomainOwner,
    required this.costToClose,
  });

  @override
  List<Object?> get props => [violationOccurred, isDomainOwner, costToClose];
}
