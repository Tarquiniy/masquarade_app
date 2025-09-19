import 'package:equatable/equatable.dart';
import 'package:masquarade_app/models/domain_model.dart';
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

class LoadCurrentUserDomain extends DomainEvent {
  final String userId;

  const LoadCurrentUserDomain(this.userId);

  @override
  List<Object?> get props => [userId];
}

class LoadUserDomains extends DomainEvent {
  final String userId;

  const LoadUserDomains(this.userId);

  @override
  List<Object?> get props => [userId];
}

class SetCurrentDomain extends DomainEvent {
  final DomainModel domain;

  const SetCurrentDomain(this.domain);

  @override
  List<Object?> get props => [domain];
}

class RestoreDomainProtectionRequested extends DomainEvent {
  final int domainId;
  final int amount;
  final String profileId;

  const RestoreDomainProtectionRequested({
    required this.domainId,
    required this.amount,
    required this.profileId,
  });

  @override
  List<Object?> get props => [domainId, amount, profileId];
}

class RestoreDomainSecurity extends DomainEvent {
  final int domainId;
  final int amount;
  final String profileId; 

  const RestoreDomainSecurity({
    required this.domainId,
    required this.amount,
    required this.profileId, 
  });
}

class UpdateDomainSecurity extends DomainEvent {
  final int domainId;
  final int newSecurity;

  const UpdateDomainSecurity(this.domainId, this.newSecurity);

  @override
  List<Object?> get props => [domainId, newSecurity];
}

class UpdateDomainMaxSecurity extends DomainEvent {
  final int domainId;
  final int newMaxSecurity;

  const UpdateDomainMaxSecurity(this.domainId, this.newMaxSecurity);

  @override
  List<Object?> get props => [domainId, newMaxSecurity];
}

class UpdateDomainIncome extends DomainEvent {
  final int domainId;
  final int newIncome;

  const UpdateDomainIncome(this.domainId, this.newIncome);

  @override
  List<Object?> get props => [domainId, newIncome];
}

class UpdateDomainViolationsCount extends DomainEvent {
  final int domainId;
  final int newViolationsCount;

  const UpdateDomainViolationsCount(this.domainId, this.newViolationsCount);

  @override
  List<Object?> get props => [domainId, newViolationsCount];
}

class UpdateDomainInfluence extends DomainEvent {
  final int domainId;
  final int newInfluence;

  const UpdateDomainInfluence(this.domainId, this.newInfluence);

  @override
  List<Object?> get props => [domainId, newInfluence];
}

class UpdateDomainSecurityAndInfluence extends DomainEvent {
  final int domainId;
  final int newSecurity;
  final int newInfluence;

  const UpdateDomainSecurityAndInfluence(this.domainId, this.newSecurity, this.newInfluence);

  @override
  List<Object?> get props => [domainId, newSecurity, newInfluence];
}

class UpdateDomainMaxSecurityAndInfluence extends DomainEvent {
  final int domainId;
  final int newMaxSecurity;
  final int newInfluence;

  const UpdateDomainMaxSecurityAndInfluence(this.domainId, this.newMaxSecurity, this.newInfluence);

  @override
  List<Object?> get props => [domainId, newMaxSecurity, newInfluence];
}

class UpdateDomainBaseIncome extends DomainEvent {
  final int domainId;
  final int newBaseIncome;

  const UpdateDomainBaseIncome(this.domainId, this.newBaseIncome);

  @override
  List<Object?> get props => [domainId, newBaseIncome];
}

class DomainsUpdated extends DomainEvent {
  final List<DomainModel> domains;

  const DomainsUpdated(this.domains);

  @override
  List<Object?> get props => [domains];
}

class ResetNeutralizedDomains extends DomainEvent {}
