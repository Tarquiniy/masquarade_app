import 'package:equatable/equatable.dart';
import 'package:masquarade_app/models/profile_model.dart';

abstract class DomainEvent extends Equatable {
  const DomainEvent();
  @override
  List<Object?> get props => [];
}

class LoadDomains extends DomainEvent {}

class RefreshDomains extends DomainEvent {
  final ProfileModel? profile;

  const RefreshDomains([this.profile]);

  @override
  List<Object?> get props => [profile];
}

class LoadUserDomain extends DomainEvent {
  final String userId;

  const LoadUserDomain(this.userId);

  @override
  List<Object?> get props => [userId];
}

// Новое событие для загрузки домена текущего пользователя
class LoadCurrentUserDomain extends DomainEvent {}
