part of 'profile_bloc.dart';

abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
}

class UpdateHunger extends ProfileEvent {
  final int newHunger;

  const UpdateHunger(this.newHunger);

  @override
  List<Object?> get props => [newHunger];
}

class SetProfile extends ProfileEvent {
  final ProfileModel profile;

  const SetProfile(this.profile);

  @override
  List<Object?> get props => [profile];
}

class UpdateProfile extends ProfileEvent {
  final ProfileModel profile;

  const UpdateProfile(this.profile);

  @override
  List<Object?> get props => [profile];
}

class ClearDomain extends ProfileEvent {
  const ClearDomain();

  @override
  List<Object?> get props => [];
}

class DestroyPillar extends ProfileEvent {
  final String pillarName;

  const DestroyPillar(this.pillarName);

  @override
  List<Object?> get props => [pillarName];
}

class UpdateInfluence extends ProfileEvent {
  final int newInfluence;
  const UpdateInfluence(this.newInfluence);

  @override
  List<Object?> get props => [newInfluence];
}