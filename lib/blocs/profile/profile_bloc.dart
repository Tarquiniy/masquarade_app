import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/profile_model.dart';
import '../../repositories/supabase_repository.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final SupabaseRepository repository;

  ProfileBloc({required this.repository}) : super(ProfileInitial()) {
    on<SetProfile>(_onSetProfile);
    on<UpdateProfile>(_onUpdateProfile);
    on<ClearDomain>(_onClearDomain);
  }

  void _onSetProfile(SetProfile event, Emitter<ProfileState> emit) {
    emit(ProfileLoaded(event.profile));
  }

  void _onUpdateProfile(UpdateProfile event, Emitter<ProfileState> emit) {
    if (state is ProfileLoaded) {
      emit(ProfileLoaded(event.profile));
    }
  }

  void _onClearDomain(ClearDomain event, Emitter<ProfileState> emit) {
    if (state is ProfileLoaded) {
      final currentProfile = (state as ProfileLoaded).profile;
      emit(ProfileLoaded(currentProfile.copyWith(domainId: null)));
    }
  }

  /// Возвращает список всех игроков, кроме текущего
  Future<List<ProfileModel>> getPlayers() async {
    final profiles = await repository.getAllProfiles();

    final currentProfile = (state is ProfileLoaded)
        ? (state as ProfileLoaded).profile
        : null;

    if (currentProfile == null) return profiles;

    return profiles.where((p) => p.id != currentProfile.id).toList();
  }
}
