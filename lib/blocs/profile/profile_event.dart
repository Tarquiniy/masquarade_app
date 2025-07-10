part of 'profile_bloc.dart';

abstract class ProfileEvent extends Equatable {
  const ProfileEvent();

  @override
  List<Object?> get props => [];
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
