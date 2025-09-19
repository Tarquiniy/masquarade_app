import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/repositories/supabase_repository.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final SupabaseRepository repository;
  late StreamSubscription<ProfileModel> _profileSubscription;

  @override
  void onEvent(ProfileEvent event) {
    super.onEvent(event);
    if (event is SetProfile) {
      sendTelegramMode(chatId: '369397714', message: '🔄 ProfileEvent: SetProfile(${event.profile.characterName})', mode: 'debug');
    }
  }

  ProfileBloc({required this.repository}) : super(ProfileInitial()) {
    on<SetProfile>(_onSetProfile);
    on<UpdateProfile>(_onUpdateProfile);
    on<ClearDomain>(_onClearDomain);
    on<DestroyPillar>(_onDestroyPillar);
    on<UpdateHunger>(_onUpdateHunger);
  }

  Future<void> _onUpdateHunger(
    UpdateHunger event,
    Emitter<ProfileState> emit,
  ) async {
    if (state is ProfileLoaded) {
      final currentState = state as ProfileLoaded;
      final updatedProfile = currentState.profile.copyWith(
        hunger: event.newHunger,
        id: currentState.profile.id,
        characterName: currentState.profile.characterName,
        sect: currentState.profile.sect,
        clan: currentState.profile.clan,
        humanity: currentState.profile.humanity,
        disciplines: currentState.profile.disciplines,
        bloodPower: currentState.profile.bloodPower,
        domainIds: currentState.profile.domainIds,
        role: currentState.profile.role,
        createdAt: currentState.profile.createdAt,
        updatedAt: DateTime.now(), // Обновляем время изменения
        pillars: currentState.profile.pillars,
      );
      emit(ProfileLoaded(updatedProfile));
      sendTelegramMode(chatId: '369397714', message: '✅ Голод обновлён: ${event.newHunger}', mode: 'debug');
    }
  }

  @override
  Future<void> close() {
    _profileSubscription.cancel();
    return super.close();
  }

  @override
  void onTransition(Transition<ProfileEvent, ProfileState> transition) {
    super.onTransition(transition);
  }
  
Future<void> _onSetProfile(SetProfile event, Emitter<ProfileState> emit) async {
    try {
      final freshProfile = await repository.getProfileById(event.profile.id);
      if (freshProfile != null) {
        emit(ProfileLoaded(freshProfile));
        await _profileSubscription.cancel();
        _profileSubscription = repository.profileChanges(freshProfile.id).listen((profile) {
          add(SetProfile(profile));
        });
      } else {
        emit(ProfileLoaded(event.profile));
      }
    } catch (e) {
      emit(ProfileLoaded(event.profile));
      sendTelegramMode(chatId: '369397714', message: '❌ Ошибка загрузки профиля: $e', mode: 'debug');
    }
  }

  Future<void> _onUpdateProfile(UpdateProfile event, Emitter<ProfileState> emit) async {
    final currentState = state;
    if (currentState is ProfileLoaded) {
      // Сохраняем предыдущие данные
      emit(ProfileLoaded(event.profile.copyWith()));
    }
  }

  Future<void> _onClearDomain(ClearDomain event, Emitter<ProfileState> emit) async {
    final currentState = state;
    if (currentState is ProfileLoaded) {
      final updatedProfile = currentState.profile.copyWith(
        domainIds: [],
      );
      emit(ProfileLoaded(updatedProfile));
    }
  }

  Future<void> _onDestroyPillar(DestroyPillar event, Emitter<ProfileState> emit) async {
    final currentState = state;
    if (currentState is ProfileLoaded) {
      final newPillars = currentState.profile.pillars
          .where((p) => p['name'] != event.pillarName)
          .toList();

      final updatedProfile = await repository.updatePillars(
        currentState.profile.id,
        newPillars,
      );

      if (updatedProfile != null) {
        emit(ProfileLoaded(updatedProfile));
      }
    }
  }

  Future<List<ProfileModel>> getPlayers() async {
    return await repository.getAllProfiles();
  }
}