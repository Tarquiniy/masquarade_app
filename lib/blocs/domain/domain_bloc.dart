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
    sendDebugToTelegram('💾 Текущий домен сохранен: ${event.domain.name}');
  }

  void _checkForNeutralDomains(List<DomainModel> newDomains, List<DomainModel> oldDomains) async {
  try {
    sendDebugToTelegram('🔍 Проверка изменений доменов. Новые: ${newDomains.length}, старые: ${oldDomains.length}');
    
    for (final newDomain in newDomains) {
      if (newDomain.isNeutral) {
        sendDebugToTelegram('🔍 Найден нейтральный домен: ${newDomain.name}');
        // Ищем этот домен в старых доменах
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

        // Если домен стал нейтральным (раньше не был нейтральным)
        if (!oldDomain.isNeutral && newDomain.isNeutral && newDomain.ownerId.isNotEmpty) {
          await _sendDomainNeutralNotification(newDomain);
        }
      }
    }
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка проверки нейтральных доменов: $e');
  }
}

Future<void> _onLoadDomains(
  LoadDomains event,
  Emitter<DomainState> emit,
) async {
  // Сохраняем текущие домены перед загрузкой новых
  final List<DomainModel> oldDomains = state is DomainsLoaded 
      ? (state as DomainsLoaded).domains 
      : [];

  emit(DomainLoading());
  try {
    final domains = await repository.getDomains();

    // Проверяем изменения isNeutral
    _checkForNeutralDomains(domains, oldDomains);

    // Проверяем, есть ли домены с защитой 0, но не нейтральные
    for (final domain in domains) {
      if (domain.securityLevel == 0 && !domain.isNeutral) {
        sendDebugToTelegram('⚠️ Обнаружен домен с защитой 0, но не нейтральный: ${domain.id}');
        await repository.setDomainNeutralFlag(domain.id, true);
      }
    }

    // Загружаем обновленные данные
    final updatedDomains = await repository.getDomains();
    emit(DomainsLoaded(updatedDomains));
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
    await sendDebugToTelegram('🔍 LoadUserDomain for user: ${event.userId}');
    final domains = await repository.getDomains();

    // Исключаем нейтральные домены из поиска
    DomainModel userDomain = domains.firstWhere(
      (d) => d.ownerId == event.userId && !d.isNeutral,
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

  @override
void onTransition(Transition<DomainEvent, DomainState> transition) {
  super.onTransition(transition);
  
  // При любом изменении состояния проверяем, нет ли доменов с защитой 0, которые не нейтральны
  if (transition.nextState is DomainsLoaded) {
    final domains = (transition.nextState as DomainsLoaded).domains;
    
    for (final domain in domains) {
      if (domain.securityLevel == 0 && !domain.isNeutral) {
        // Немедленно исправляем это
        sendDebugToTelegram('⚠️ Обнаружен домен с защитой 0, но не нейтральный: ${domain.id}');
        repository.forceDomainNeutralization(domain.id);
      }
    }
  }
}

  Future<void> _cacheDomains(List<DomainModel> domains) async {
    try {
      final jsonString = jsonEncode(domains.map((e) => e.toJson()).toList());
      await prefs.setString('cachedDomains', jsonString);
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка кеширования доменов: $e');
    }
  }

  Future<void> _onUpdateDomainSecurity(
  UpdateDomainSecurity event,
  Emitter<DomainState> emit,
) async {
  if (state is DomainsLoaded) {
    try {
      sendDebugToTelegram('🔄 DomainBloc: обновление доменов после изменения защиты');

      // Принудительно загружаем свежие данные
      final domains = await repository.getDomains();

      // Проверяем, есть ли домены с защитой 0, но не нейтральные
      for (final domain in domains) {
        if (domain.securityLevel == 0 && !domain.isNeutral) {
          sendDebugToTelegram('⚠️ Обнаружен домен с защитой 0, но не нейтральный: ${domain.id}');
          await repository.setDomainNeutralFlag(domain.id, true);
          
          // Отправляем уведомление владельцу
          await _sendDomainNeutralNotification(domain);
        }
      }

      // Загружаем обновленные данные
      final updatedDomains = await repository.getDomains();
      emit(DomainsLoaded(updatedDomains));
      await _cacheDomains(updatedDomains);

      sendDebugToTelegram('✅ DomainBloc: домены обновлены');
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка обновления доменов: $e');
    }
  }
}

Future<void> sendTelegramMessageDirect(String chatId, String message) async {
  try {
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
      sendDebugToTelegram('Telegram error for $chatId: ${response.body}');
    }
  } catch (e) {
    sendDebugToTelegram('Telegram send to $chatId failed: $e');
  }
}

Future<void> _sendDomainNeutralNotification(DomainModel domain) async {
  try {
    sendDebugToTelegram('🔔 Попытка отправить уведомление о нейтрализации домена ${domain.name}');

    // Получаем профиль владельца домена
    final ownerProfile = await repository.getProfileById(domain.ownerId);
    if (ownerProfile == null || ownerProfile.telegramChatId == null) {
      sendDebugToTelegram('❌ Владелец домена не найден или не имеет telegram_chat_id');
      return;
    }

    // Формируем сообщение
    final message =
      '⚠️ ВАЖНО: Домен "${domain.name}" стал нейтральным!\n'
      'Защита домена упала до 0. Вы больше не контролируете эту территорию.';

    // Отправляем уведомление через бота
    await sendTelegramMessageDirect(ownerProfile.telegramChatId!, message);

    sendDebugToTelegram('✅ Уведомление о нейтрализации отправлено владельцу домена ${domain.name}');
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка отправки уведомления о нейтрализации домена: $e');
  }
}
}