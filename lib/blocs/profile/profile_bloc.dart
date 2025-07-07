import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../models/profile_model.dart';

part 'profile_event.dart';
part 'profile_state.dart';

class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  ProfileBloc() : super(ProfileInitial()) {
    on<SetProfile>(_onSetProfile);
  }

  void _onSetProfile(SetProfile event, Emitter<ProfileState> emit) {
    emit(ProfileLoaded(event.profile));
  }
}
