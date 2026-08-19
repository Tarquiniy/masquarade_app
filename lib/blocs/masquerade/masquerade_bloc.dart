import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tankograd/blocs/domain/domain_bloc.dart';
import 'package:tankograd/blocs/domain/domain_event.dart';
import 'package:tankograd/blocs/profile/profile_bloc.dart';
import 'package:tankograd/utils/debug_telegram.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../models/violation_model.dart';
import '../../models/profile_model.dart';
import '../../models/domain_model.dart';
import '../../repositories/supabase_repository.dart';

part 'masquerade_event.dart';
part 'masquerade_state.dart';

class MasqueradeBloc extends Bloc<MasqueradeEvent, MasqueradeState> {
  final DomainBloc domainBloc;
  final SupabaseRepository repository;
  ProfileModel currentProfile;
  final Random _random = Random();
  final Uuid _uuid = const Uuid();
  final ProfileBloc profileBloc;
  StreamSubscription? _profileSubscription;
  late final SharedPreferences prefs;

  MasqueradeBloc({
    required this.repository,
    required this.currentProfile,
    required this.profileBloc,
    required this.domainBloc,
    List<ViolationModel>? cachedViolations,
  }) : super(cachedViolations != null ? ViolationsLoaded(cachedViolations) : ViolationsLoading()) {
    // Инициализация SharedPreferences
    _initPrefs();

    // Подписка на обновления профиля
    _profileSubscription = profileBloc.stream.listen((state) {
      if (state is ProfileLoaded) {
        currentProfile = state.profile;
      }
    });

    on<LoadViolations>(_onLoadViolations);
    on<LoadViolationsForDomain>(_onLoadViolationsForDomain);
    on<ReportViolation>(_onReportViolation);
    on<StartHunt>(_onStartHunt);
    on<CloseViolation>(_onCloseViolation);
    on<RevealViolator>(_onRevealViolator);
    on<UpdateCurrentProfile>((event, emit) {
  currentProfile = event.profile;
});
  }

  Future<void> _initPrefs() async {
    prefs = await SharedPreferences.getInstance();
  }

  @override
  Future<void> close() {
    _profileSubscription?.cancel();
    return super.close();
  }

  Future<void> _onLoadViolations(
    LoadViolations event,
    Emitter<MasqueradeState> emit,
  ) async {
    if (state is! ViolationsLoaded) {
      emit(ViolationsLoading());
    }

    try {
      final list = await repository.getViolations();

      // Сохраняем нарушения в кеш
      final jsonString = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString('cachedViolations', jsonString);

      await sendTelegramMode(chatId: '369397714', message: '✅ Нарушения успешно загружены\nКоличество: ${list.length}\n'
        'Примеры: ${list.take(3).map((v) => '${v.id}: ${v.description}').join('\n')}', mode: 'debug');

      emit(ViolationsLoaded(list));
    } catch (e) {
      final errorMsg = '❌ Ошибка загрузки нарушений: ${e.toString()}';
      print(errorMsg);
      emit(ViolationsError('Ошибка загрузки нарушений'));
    }
  }


  Future<void> _onLoadViolationsForDomain(
  LoadViolationsForDomain event,
  Emitter<MasqueradeState> emit,
) async {
  emit(ViolationsLoading());
  try {
    final list = await repository.getViolationsByDomainId(event.domainId);
    emit(ViolationsLoaded(list));
  } catch (e) {
    emit(ViolationsError('Ошибка загрузки нарушений'));
  }
}

  Future<void> _onReportViolation(
    ReportViolation event,
    Emitter<MasqueradeState> emit,
  ) async {
    try {
      // Проверка на максимальный голод
      if (currentProfile.hunger + event.hungerSpent > 5) {
        emit(const ViolationsError('max_hunger_exceeded'));
        return;
      }

      await _createViolation(
        description: event.description,
        hungerSpent: event.hungerSpent,
        latitude: event.latitude,
        longitude: event.longitude,
        domainId: event.domainId,
        isHunt: false, // Ручное нарушение, не охота
        emit: emit,
      );
    } catch (e) {
      emit(const ViolationsError('Не удалось создать нарушение'));
    }
  }


Future<void> _onStartHunt(
  StartHunt event,
  Emitter<MasqueradeState> emit,
) async {
  try {
    // Получаем свежий профиль напрямую из базы
    final freshProfile = await repository.getProfileById(currentProfile.id);
    if (freshProfile == null) {
      emit(const ViolationsError('Профиль не найден'));
      return;
    }

    final currentHunger = freshProfile.hunger;

    // Проверяем, что голод > 0
    if (currentHunger <= 0) {
      emit(const ViolationsError('hunt_with_zero_hunger'));
      return;
    }

    final newHunger = currentHunger - 1;
    final clampedHunger = newHunger > 0 ? newHunger : 0;

    // Обновляем голод в базе
    final updatedHunger = await repository.updateHunger(
      freshProfile.id,
      clampedHunger
    );

    if (updatedHunger != null) {
      // Обновляем ProfileBloc
      profileBloc.add(UpdateHunger(updatedHunger));
      await sendTelegramMode(chatId: '369397714', message: '✅ Голод обновлён: $clampedHunger', mode: 'debug');
    }

      final violationProbability = event.isDomainOwner ? 0.25 : 0.5;
      final violationOccurs = _random.nextDouble() < violationProbability;

      String huntResultMessage = '✅ Охота завершена';
      String violationMessage = '';
      int costToClose = 0;

      if (violationOccurs) {
        costToClose = event.isDomainOwner ? 1 : 2;

        await _createViolation(
          description: 'Неосторожная охота',
          hungerSpent: 1,
          latitude: event.position.latitude,
          longitude: event.position.longitude,
          domainId: event.domainId,
          emit: emit,
          isHunt: true,
        );

        violationMessage = '\n⚠️ Нарушение было зафиксировано';
      }

      // Обновляем список нарушений после охоты
      add(LoadViolationsForDomain(event.domainId));

      emit(
        HuntCompleted(
          violationOccurred: violationOccurs,
          isDomainOwner: event.isDomainOwner,
          costToClose: violationOccurs ? costToClose : 0,
          newHunger: clampedHunger, // Добавляем новый уровень голода
        ),
      );
    } catch (e, stack) {
      final errorDetails = '❌ Ошибка во время охоты: ${e.toString()}\n$stack';
      emit(ViolationsError(errorDetails));
    }
  }

  Future<void> _onCloseViolation(
    CloseViolation event,
    Emitter<MasqueradeState> emit,
  ) async {
    try {
      final violation = await repository.getViolationById(event.violationId);
      if (violation == null || !violation.canBeClosed) {
        emit(ViolationsError('Нарушение уже закрыто или не существует'));
        return;
      }

      final domain = await repository.getDomainById(violation.domainId);
      if (domain == null || domain.ownerId != currentProfile.id) {
        emit(ViolationsError('Вы не владеете этим доменом'));
        return;
      }

      // Используем только влияние домена
      final domainInfluence = domain.influenceLevel;
      if (domainInfluence < violation.costToClose) {
        emit(
          ViolationsError(
            'Недостаточно влияния домена для закрытия нарушения. '
            'Требуется: ${violation.costToClose}, '
            'Влияние домена: $domainInfluence',
          ),
        );
        return;
      }

      // Обновляем влияние домена перед закрытием
      await repository.updateDomainInfluence(
        domain.id,
        domain.adminInfluence - violation.costToClose,
      );

      await repository.closeViolation(violation.id, currentProfile.id);

      // Обновляем список нарушений для этого домена
      add(LoadViolationsForDomain(domain.id));
      emit(ViolationClosedSuccessfully());
    } catch (e) {
      emit(ViolationsError('Ошибка при закрытии нарушения: ${e.toString()}'));
    }
  }

  Future<void> _onRevealViolator(
    RevealViolator event,
    Emitter<MasqueradeState> emit,
  ) async {
    try {
      final violation = await repository.getViolationById(event.violationId);
      if (violation == null || !violation.canBeRevealed) {
        emit(ViolationsError('Нарушитель уже раскрыт или невозможно раскрыть'));
        return;
      }

      final violatorProfile = await repository.getProfileById(
        violation.violatorId,
      );
      if (violatorProfile == null) {
        emit(ViolationsError('Профиль нарушителя не найден'));
        return;
      }

      final domain = await repository.getDomainById(violation.domainId);
      if (domain == null) {
        emit(ViolationsError('Домен не найден'));
        return;
      }

      // Используем только влияние домена
      final domainInfluence = domain.influenceLevel;
      if (domainInfluence < violation.costToReveal) {
        emit(
          ViolationsError(
            'Недостаточно влияния домена для раскрытия. '
            'Требуется: ${violation.costToReveal}, '
            'Влияние домена: $domainInfluence',
          ),
        );
        return;
      }

      // Обновляем влияние домена перед раскрытием
      await repository.updateDomainInfluence(
        domain.id,
        domain.adminInfluence - violation.costToReveal,
      );

      await repository.revealViolation(
        id: violation.id,
        violatorName: violatorProfile.characterName,
        revealedAt: DateTime.now().toIso8601String(),
      );

      // Обновляем список нарушений для этого домена
      add(LoadViolationsForDomain(domain.id));
      emit(ViolatorRevealedSuccessfully());
    } catch (e) {
      emit(ViolationsError('Ошибка при раскрытии нарушителя: ${e.toString()}'));
    }
  }

  Future<void> _createViolation({
  required String description,
  required int hungerSpent,
  required double latitude,
  required double longitude,
  required int domainId,
  required bool isHunt,
  required Emitter<MasqueradeState> emit,
}) async {
  final id = _uuid.v4();
  final message = '🚨 Нарушение маскарада\n'
    'Игрок: ${currentProfile.characterName} (${currentProfile.id})\n'
    'Описание: $description\n'
    'Голод: $hungerSpent\n'
    'Тип: ${isHunt ? "Охота" : "Ручное"}\n'
    'Домен: $domainId\n'
    'Координаты: $latitude, $longitude';
  await sendTelegramMode(chatId: '369397714', message: message, mode: 'debug');

  final violation = ViolationModel(
    id: id,
    violatorId: currentProfile.id,
    violatorName: null,
    domainId: domainId,
    description: description,
    hungerSpent: hungerSpent,
    costToClose: hungerSpent * 2,
    costToReveal: hungerSpent,
    status: ViolationStatus.open,
    violatorKnown: false,
    createdAt: DateTime.now(),
    latitude: latitude,
    longitude: longitude,
    closedAt: null,
    revealedAt: null,
    resolvedBy: null,
  );

  await repository.createViolation(violation);

  // Уменьшаем защиту домена на 1
{
  final domain = await repository.getDomainById(domainId);
  if (domain != null && !domain.isNeutral) {
    int newSecurity = domain.securityLevel - 1;

    // Защита не может быть отрицательной
    if (newSecurity < 0) newSecurity = 0;

    // Обновляем защиту домена в базе данных
    await repository.updateDomainSecurity(domainId, newSecurity);

    // Если защита стала 0, принудительно устанавливаем флаг нейтральности
    if (newSecurity == 0) {
  await repository.setDomainNeutralFlag(domainId, true);

  // Отправляем уведомление владельцу домена
  if (domain.ownerId.isNotEmpty) {
    final ownerProfile = await repository.getProfileById(domain.ownerId);
    if (ownerProfile != null && ownerProfile.telegramChatId != null) {
      final message =
        '⚠️ ВАЖНО: Домен "${domain.name}" стал нейтральным!\n'
        'Защита домена упала до 0 из-за нарушения Маскарада. Вы больше не контролируете эту территорию.';

      //await sendTelegramMessageDirect(
      //  ownerProfile.telegramChatId!,
      //  message,
      //);

      sendTelegramMode(chatId: ownerProfile.telegramChatId!, message: message, mode: 'notification');
    }
  }

  // Принудительно обновляем список доменов
  domainBloc.add(LoadDomains());

  // УДАЛЕНО: Обновление профиля владельца через profileBloc
  // Это было причиной проблемы с отображением чужого профиля
    }
    // Уведомляем DomainBloc об изменении защиты
    domainBloc.add(UpdateDomainSecurity(domainId, newSecurity));

    // Увеличиваем счетчик открытых нарушений
    await repository.incrementDomainViolationsCount(domainId);
  }
}

  // Только для ручных нарушений увеличиваем голод
  if (!isHunt) {
    final newHunger = currentProfile.hunger + hungerSpent;
    final updatedHunger = await repository.updateHunger(
      currentProfile.id,
      newHunger,
    );
    if (updatedHunger != null) {
      profileBloc.add(UpdateHunger(updatedHunger));
    }
  }

  // После создания — обновляем список нарушений для домена
  add(LoadViolationsForDomain(domainId));
  emit(ViolationReportedSuccessfully());
}
}