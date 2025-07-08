import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'domain_event.dart';
import 'domain_state.dart';
import '../../repositories/supabase_repository.dart';

class DomainBloc extends Bloc<DomainEvent, DomainState> {
  final SupabaseRepository repository;

  DomainBloc({required this.repository}) : super(DomainInitial()) {
    on<LoadDomains>(_onLoadDomains);
    on<RefreshDomains>(_onRefreshDomains);
    on<LoadUserDomain>(_onLoadUserDomain);
  }

  Future<void> _onLoadDomains(
    LoadDomains event,
    Emitter<DomainState> emit,
  ) async {
    emit(DomainLoading());
    try {
      final domains = await repository.getDomains();
      final profile = await repository.getCurrentProfile();

      if (profile != null) {
        await sendDebugToTelegram('📌 Profile ID: ${profile.id}');
        for (final d in domains) {
          final match = d.ownerId == profile.id ? '✅' : '❌';
          await sendDebugToTelegram('🏰 ${d.name} → ${d.ownerId} $match');
        }
      } else {
        await sendDebugToTelegram('❗️Profile is null in DomainBloc');
      }

      emit(DomainsLoaded(domains));
    } catch (e) {
      await sendDebugToTelegram('❌ Ошибка в LoadDomains: $e');
      emit(DomainError('Не удалось загрузить домены'));
    }
  }

  Future<void> _onRefreshDomains(
    RefreshDomains event,
    Emitter<DomainState> emit,
  ) async {
    try {
      final domains = await repository.getDomains();
      final profile = await repository.getCurrentProfile();

      if (profile != null) {
        await sendDebugToTelegram('🔄 Refresh — Profile ID: ${profile.id}');
        for (final d in domains) {
          final match = d.ownerId == profile.id ? '✅' : '❌';
          await sendDebugToTelegram('🏰 ${d.name} → ${d.ownerId} $match');
        }
      } else {
        await sendDebugToTelegram('❗️Profile is null in RefreshDomains');
      }

      emit(DomainsLoaded(domains));
    } catch (e) {
      await sendDebugToTelegram('❌ Ошибка в RefreshDomains: $e');
      emit(DomainError('Не удалось обновить домены'));
    }
  }

  Future<void> _onLoadUserDomain(
    LoadUserDomain event,
    Emitter<DomainState> emit,
  ) async {
    try {
      final domains = await repository.getDomains();
      final userDomain = domains.firstWhere(
        (d) => d.ownerId == event.userId,
        orElse: () => DomainModel(
          id: -1,
          name: 'No domain',
          latitude: 0,
          longitude: 0,
          boundaryPoints: [],
          ownerId: '',
        ),
      );

      emit(UserDomainLoaded(userDomain));
    } catch (e) {
      await sendDebugToTelegram('❌ Ошибка загрузки домена пользователя: $e');
      emit(DomainError('Не удалось загрузить домен'));
    }
  }
}
