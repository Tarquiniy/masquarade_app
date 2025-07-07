import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/profile_model.dart';
import '../../repositories/supabase_repository.dart';
import '../../utils/debug_telegram.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final SupabaseRepository repository;

  AuthBloc({required this.repository}) : super(AuthInitial()) {
    on<UsernameSubmitted>(_onUsernameSubmitted);
    on<LogoutRequested>(_onLogout);
  }

  Future<void> _onUsernameSubmitted(
    UsernameSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      final profile = await repository.getProfileByTelegram(
        event.username,
        debug: (msg) {
          print('[DEBUG AUTH] $msg');
          sendDebugToTelegram('[DEBUG AUTH] $msg');
        },
      );

      if (profile == null) {
        emit(AuthFailure('not_found'));
        return;
      }

      emit(Authenticated(profile));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  void _onLogout(LogoutRequested event, Emitter<AuthState> emit) {
    emit(AuthInitial());
  }
}
