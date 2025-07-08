import 'package:equatable/equatable.dart';

abstract class DomainEvent extends Equatable {
  const DomainEvent();
  @override
  List<Object?> get props => [];
}

class LoadDomains extends DomainEvent {}

class RefreshDomains extends DomainEvent {}

// Новое событие
class LoadUserDomain extends DomainEvent {
  final String userId;

  const LoadUserDomain(this.userId);

  @override
  List<Object?> get props => [userId];
}
