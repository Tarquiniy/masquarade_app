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
    on<LoadUserDomains>(_onLoadUserDomains);
  }

  Future<void> _onLoadDomains(
    LoadDomains event,
    Emitter<DomainState> emit,
  ) async {
    emit(DomainLoading());
    try {
      final domains = await repository.getDomains();
      emit(DomainsLoaded(domains));
      await sendDebugToTelegram('✅ LoadDomains — loaded ${domains.length} domains');
    } catch (e) {
      await sendDebugToTelegram('❌ LoadDomains error: $e');
      emit(DomainError('Не удалось загрузить домены'));
    }
  }

  Future<void> _onRefreshDomains(
    RefreshDomains event,
    Emitter<DomainState> emit,
  ) async {
    if (event.profile == null) {
      emit(DomainError('Профиль не передан в RefreshDomains'));
      await sendDebugToTelegram('❗️ RefreshDomains: Профиль не передан!');
      return;
    }

    emit(DomainLoading());
    try {
      final domains = await repository.getDomains();
      emit(DomainsLoaded(domains));

      await sendDebugToTelegram(
        '🔄 RefreshDomains — Profile ID: ${event.profile!.id}',
      );

      for (final d in domains) {
        final match = d.ownerId == event.profile!.id ? '✅' : '❌';
        await sendDebugToTelegram('🏰 ${d.name} → ${d.ownerId} $match');
      }
    } catch (e) {
      await sendDebugToTelegram('❌ RefreshDomains error: $e');
      emit(DomainError('Не удалось обновить домены'));
    }
  }

  Future<void> _onLoadUserDomain(
    LoadUserDomain event,
    Emitter<DomainState> emit,
  ) async {
    emit(DomainLoading());
    try {
      await sendDebugToTelegram('🔍 LoadUserDomain for user: ${event.userId}');
      final domains = await repository.getDomains();

      DomainModel userDomain = domains.firstWhere(
        (d) => d.ownerId == event.userId,
        orElse: () {
          sendDebugToTelegram(
            '⚠️ UserDomain: домен не найден для пользователя ${event.userId}',
          );
          return DomainModel(
            id: -1,
            name: 'Нет домена',
            latitude: 0,
            longitude: 0,
            boundaryPoints: [],
            ownerId: '',
          );
        },
      );

      await sendDebugToTelegram('✅ Found domain: ${userDomain.name}');
      emit(UserDomainLoaded(userDomain));
    } catch (e) {
      await sendDebugToTelegram('❌ LoadUserDomain error: $e');
      emit(DomainError('Не удалось загрузить домен'));
    }
  }

  // Новый обработчик для загрузки всех доменов пользователя
  Future<void> _onLoadUserDomains(
    LoadUserDomains event,
    Emitter<DomainState> emit,
  ) async {
    emit(DomainLoading());
    try {
      final domains = await repository.getDomains();
      final userDomains = domains
          .where((d) => d.ownerId == event.userId)
          .toList();
      
      emit(UserDomainsLoaded(userDomains));
      await sendDebugToTelegram(
        '✅ LoadUserDomains — loaded ${userDomains.length} domains for user ${event.userId}'
      );
    } catch (e) {
      await sendDebugToTelegram('❌ LoadUserDomains error: $e');
      emit(DomainError('Не удалось загрузить домены пользователя'));
    }
  }
}