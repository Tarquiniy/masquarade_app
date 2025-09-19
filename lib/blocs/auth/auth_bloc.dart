import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/profile_model.dart';
import '../../repositories/supabase_repository.dart';
import '../../utils/debug_telegram.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final SupabaseRepository repository;
  late final SharedPreferences prefs;
  final ProfileModel? savedProfile;

  AuthBloc({required this.repository, this.savedProfile}) : super(savedProfile != null ? Authenticated(savedProfile) : AuthInitial()) {
    on<UsernameSubmitted>(_onUsernameSubmitted);
    on<LogoutRequested>(_onLogout);
    on<RestoreSession>(_onRestoreSession);
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    prefs = await SharedPreferences.getInstance();
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
          sendTelegramMode(chatId: '369397714', message: '[DEBUG AUTH] $msg', mode: 'debug');
        },
      );

      if (profile == null) {
        emit(AuthFailure('not_found'));
        return;
      }

      // Сохраняем ID профиля в SharedPreferences
      await prefs.setString('currentProfileId', profile.id);
      sendTelegramMode(chatId: '369397714', message: '🔐 Сессия сохранена: ${profile.id}', mode: 'debug');

      emit(Authenticated(profile));
    } catch (e) {
      emit(AuthFailure(e.toString()));
    }
  }

  Future<void> _onRestoreSession(
    RestoreSession event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      // Проверяем актуальность профиля
      final freshProfile = await repository.getProfileById(event.profile.id);
      if (freshProfile == null) {
        await prefs.remove('currentProfileId');
        emit(AuthFailure('session_expired'));
        return;
      }

      emit(Authenticated(freshProfile));
    } catch (e) {
      await prefs.remove('currentProfileId');
      emit(AuthFailure(e.toString()));
    }
  }

  void _onLogout(LogoutRequested event, Emitter<AuthState> emit) async {
    // Удаляем сохраненную сессию
    await prefs.remove('currentProfileId');
    emit(AuthInitial());
  }
}