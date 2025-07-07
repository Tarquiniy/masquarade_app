import 'package:equatable/equatable.dart';
import '../../models/domain_model.dart';

abstract class DomainState extends Equatable {
  const DomainState();
  @override
  List<Object?> get props => [];
}

class DomainInitial extends DomainState {}

class DomainLoading extends DomainState {}

class DomainsLoaded extends DomainState {
  final List<DomainModel> domains;

  const DomainsLoaded(this.domains);

  @override
  List<Object?> get props => [domains];
}

class DomainError extends DomainState {
  final String message;

  const DomainError(this.message);

  @override
  List<Object?> get props => [message];
}
