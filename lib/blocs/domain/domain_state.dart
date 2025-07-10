import 'package:equatable/equatable.dart';
import 'package:masquarade_app/models/domain_model.dart';

abstract class DomainState extends Equatable {
  const DomainState();

  @override
  List<Object?> get props => [];
}

class DomainInitial extends DomainState {}

class DomainLoading extends DomainState {}

class DomainError extends DomainState {
  final String message;
  const DomainError(this.message);

  @override
  List<Object?> get props => [message];
}

class DomainsLoaded extends DomainState {
  final List<DomainModel> domains;
  const DomainsLoaded(this.domains);

  @override
  List<Object?> get props => [domains];
}

class UserDomainLoaded extends DomainState {
  final DomainModel domain;
  const UserDomainLoaded(this.domain);

  @override
  List<Object?> get props => [domain];
}

class CurrentUserDomainLoaded extends DomainState {
  final DomainModel domain;
  const CurrentUserDomainLoaded(this.domain);

  @override
  List<Object?> get props => [domain];
}
