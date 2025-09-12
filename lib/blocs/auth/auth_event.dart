part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class UsernameSubmitted extends AuthEvent {
  final String username;

  const UsernameSubmitted(this.username);

  @override
  List<Object?> get props => [username];
}

class LogoutRequested extends AuthEvent {}

class RestoreSession extends AuthEvent {
  final ProfileModel profile;

  const RestoreSession(this.profile);

  @override
  List<Object?> get props => [profile];
}