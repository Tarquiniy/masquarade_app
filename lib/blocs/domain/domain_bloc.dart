import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain_event.dart';
import 'domain_state.dart';
import '../../repositories/supabase_repository.dart';

class DomainBloc extends Bloc<DomainEvent, DomainState> {
  final SupabaseRepository repository;
  final SharedPreferences prefs;
  DomainModel? currentDomain;

  DomainBloc({
  required this.repository,
  required this.prefs,
  List<DomainModel>? cachedDomains,
  DomainModel? cachedCurrentDomain,
}) : super(cachedDomains != null ? DomainsLoaded(cachedDomains) : DomainInitial()) {
  currentDomain = cachedCurrentDomain;

  on<LoadDomains>(_onLoadDomains);
  on<RefreshDomains>(_onRefreshDomains);
  on<LoadUserDomain>(_onLoadUserDomain);
  on<SetCurrentDomain>(_onSetCurrentDomain);
  on<UpdateDomainSecurity>(_onUpdateDomainSecurity);
  on<UpdateDomainBaseIncome>(_onUpdateDomainBaseIncome);
  on<ResetNeutralizedDomains>((event, emit) {
  if (state is DomainsLoaded) {
    emit(DomainsLoaded((state as DomainsLoaded).domains));
  }
});
}

    Future<void> _onDomainsUpdated(
    DomainsUpdated event,
    Emitter<DomainState> emit,
  ) async {
    final currentState = state;
    List<DomainModel> oldDomains = [];
    if (currentState is DomainsLoaded) {
      oldDomains = currentState.domains;
    }

    emit(DomainsLoaded(event.domains));
    _checkForNeutralDomains(event.domains, oldDomains);
  }

  Future<void> _onSetCurrentDomain(
    SetCurrentDomain event,
    Emitter<DomainState> emit,
  ) async {
    currentDomain = event.domain;
    await prefs.setString('currentDomain', jsonEncode(event.domain.toJson()));
  }

  List<DomainModel> _checkForNeutralDomains(List<DomainModel> newDomains, List<DomainModel> oldDomains) {
  List<DomainModel> neutralized = [];
  for (final newDomain in newDomains) {
    if (newDomain.isNeutral) {
      final oldDomain = oldDomains.firstWhere(
        (domain) => domain.id == newDomain.id,
        orElse: () => DomainModel(
          id: -1,
          name: '',
          latitude: 0,
          longitude: 0,
          boundaryPoints: [],
          ownerId: '',
          isNeutral: false,
        ),
      );

      if (!oldDomain.isNeutral && newDomain.isNeutral && newDomain.ownerId.isNotEmpty) {
        neutralized.add(newDomain);
        _sendDomainNeutralNotification(newDomain);
      }
    }
  }
  return neutralized;
}

Future<void> _onLoadDomains(
  LoadDomains event,
  Emitter<DomainState> emit,
) async {
  List<DomainModel> oldDomains = [];
  if (state is DomainsLoaded) {
    oldDomains = (state as DomainsLoaded).domains;
  }

  emit(DomainLoading());
  try {
    final domains = await repository.getDomains();
    final neutralizedDomains = _checkForNeutralDomains(domains, oldDomains);

    for (final domain in domains) {
      if (domain.securityLevel == 0 && !domain.isNeutral) {
        await repository.setDomainNeutralFlag(domain.id, true);
      }
    }

    final updatedDomains = await repository.getDomains();
    emit(DomainsLoaded(updatedDomains, neutralizedDomains));
    await _cacheDomains(updatedDomains);
  } catch (e) {
    emit(DomainError('Не удалось загрузить домены'));
  }
}

  Future<void> _onRefreshDomains(
    RefreshDomains event,
    Emitter<DomainState> emit,
  ) async {
    emit(DomainLoading());
    try {
      final domains = await repository.getDomains();
      emit(DomainsLoaded(domains));
    } catch (e) {
      emit(DomainError('Не удалось обновить домены'));
    }
  }

  Future<void> _onLoadUserDomain(
  LoadUserDomain event,
  Emitter<DomainState> emit,
) async {
  emit(DomainLoading());
  try {
    await sendTelegramMode(chatId: '369397714', message: '🔍 LoadUserDomain for user: ${event.userId}', mode: 'debug');
    final domains = await repository.getDomains();

    // Исключаем нейтральные домены из поиска
    DomainModel userDomain = domains.firstWhere(
      (d) => d.ownerId == event.userId && !d.isNeutral,
      orElse: () {
        sendTelegramMode(chatId: '369397714', message: '⚠️ UserDomain: домен не найден для пользователя ${event.userId}', mode: 'debug');
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
    emit(UserDomainLoaded(userDomain));
  } catch (e) {
    emit(DomainError('Не удалось загрузить домен'));
  }
}

  @override
void onTransition(Transition<DomainEvent, DomainState> transition) {
  super.onTransition(transition);
  
  // При любом изменении состояния проверяем, нет ли доменов с защитой 0, которые не нейтральны
  if (transition.nextState is DomainsLoaded) {
    final domains = (transition.nextState as DomainsLoaded).domains;
    
    for (final domain in domains) {
      if (domain.securityLevel == 0 && !domain.isNeutral) {
        // Немедленно исправляем это
        repository.forceDomainNeutralization(domain.id);
      }
    }
  }
}

  Future<void> _onUpdateDomainBaseIncome(
  UpdateDomainBaseIncome event,
  Emitter<DomainState> emit,
) async {
  if (state is DomainsLoaded) {
    final domains = (state as DomainsLoaded).domains;
    final updatedDomains = domains.map((domain) {
      if (domain.id == event.domainId) {
        return domain.copyWith(baseIncome: event.newBaseIncome);
      }
      return domain;
    }).toList();

    emit(DomainsLoaded(updatedDomains));
    await _cacheDomains(updatedDomains);
  }
}

  Future<void> _cacheDomains(List<DomainModel> domains) async {
    {
      final jsonString = jsonEncode(domains.map((e) => e.toJson()).toList());
      await prefs.setString('cachedDomains', jsonString);
    }
  }

  Future<void> _onUpdateDomainSecurity(
  UpdateDomainSecurity event,
  Emitter<DomainState> emit,
) async {
  if (state is DomainsLoaded) {
    {

      // Принудительно загружаем свежие данные
      final domains = await repository.getDomains();

      // Проверяем, есть ли домены с защитой 0, но не нейтральные
      for (final domain in domains) {
        if (domain.securityLevel == 0 && !domain.isNeutral) {
          await repository.setDomainNeutralFlag(domain.id, true);
          
          // Отправляем уведомление владельцу
          await _sendDomainNeutralNotification(domain);
        }
      }

      // Загружаем обновленные данные
      final updatedDomains = await repository.getDomains();
      emit(DomainsLoaded(updatedDomains));
      await _cacheDomains(updatedDomains);

    }
  }
}

Future<void> sendTelegramMessageDirect(String chatId, String message) async {
  {
    const notificationBotToken = '8398725116:AAHlIONC2IMvX54M6jtFpAiwIRTpgzZ6DVk';
    final url = Uri.parse(
      'https://api.telegram.org/bot$notificationBotToken/sendMessage',
    );

    final response = await http.post(
      url,
      body: {
        'chat_id': chatId,
        'text': message,
        'parse_mode': 'HTML'
      },
    );

    if (response.statusCode != 200) {
    }
  }
}

Future<void> _sendDomainNeutralNotification(DomainModel domain) async {
  try {
    sendTelegramMode(chatId: '369397714', message: '🔔 Попытка отправить уведомление о нейтрализации домена ${domain.name}', mode: 'debug');

    // Получаем профиль владельца домена
    final ownerProfile = await repository.getProfileById(domain.ownerId);
    if (ownerProfile == null || ownerProfile.telegramChatId == null) {
      sendTelegramMode(chatId: '369397714', message: '❌ Владелец домена не найден или не имеет telegram_chat_id', mode: 'debug');
      return;
    }

    // Формируем сообщение
    final message =
      '⚠️ ВАЖНО: Домен "${domain.name}" стал нейтральным!\n'
      'Защита домена упала до 0. Вы больше не контролируете эту территорию.';

    // Отправляем уведомление через бота
    await sendTelegramMessageDirect(ownerProfile.telegramChatId!, message);

    sendTelegramMode(chatId: '369397714', message: '✅ Уведомление о нейтрализации отправлено владельцу домена ${domain.name}', mode: 'debug');
  } catch (e) {
  }
}
}