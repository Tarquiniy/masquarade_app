import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:uuid/uuid.dart';

import '../../models/violation_model.dart';
import '../../models/profile_model.dart';
import '../../models/domain_model.dart';
import '../../repositories/supabase_repository.dart';

part 'masquerade_event.dart';
part 'masquerade_state.dart';

class MasqueradeBloc extends Bloc<MasqueradeEvent, MasqueradeState> {
  final SupabaseRepository repository;
  final ProfileModel currentProfile;
  final Random _random = Random();
  final Uuid _uuid = const Uuid();
  final ProfileBloc profileBloc;

  MasqueradeBloc({
    required this.repository,
    required this.currentProfile,
    required this.profileBloc,
  }) : super(ViolationsLoading()) {
    on<LoadViolations>(_onLoadViolations);
    on<ReportViolation>(_onReportViolation);
    on<StartHunt>(_onStartHunt);
    on<CloseViolation>(_onCloseViolation);
    on<RevealViolator>(_onRevealViolator);
  }

  Future<void> _onLoadViolations(
    LoadViolations event,
    Emitter<MasqueradeState> emit,
  ) async {
    emit(ViolationsLoading());
    try {
      final list = await repository.getViolations();
      await sendDebugToTelegram(
        '✅ Нарушения успешно загружены\nКоличество: ${list.length}',
      );
      emit(ViolationsLoaded(list));
    } catch (e) {
      final errorMsg = '❌ Ошибка загрузки нарушений: ${e.toString()}';
      print(errorMsg);
      await sendDebugToTelegram(errorMsg);
      emit(ViolationsError('Ошибка загрузки нарушений'));
    }
  }

  Future<void> _onReportViolation(
    ReportViolation event,
    Emitter<MasqueradeState> emit,
  ) async {
    try {
      await _createViolation(
        description: event.description,
        hungerSpent: event.hungerSpent,
        latitude: event.latitude,
        longitude: event.longitude,
        domainId: event.domainId,
        isHunt: false, // Ручное нарушение, не охота
        emit: emit,
      );
    } catch (e, stack) {
      await sendDebugToTelegram('❌ Ошибка при ручном нарушении: $e\n$stack');
      emit(const ViolationsError('Не удалось создать нарушение'));
    }
  }

  Future<void> _onStartHunt(
  StartHunt event,
  Emitter<MasqueradeState> emit,
) async {
  try {
    final domainDebugInfo = 'Домен: ${event.domainId}';

    await sendDebugToTelegram(
      '🔍 Начата охота\n'
      'Игрок: ${currentProfile.characterName} (${currentProfile.id})\n'
      '$domainDebugInfo\n'
      'Владелец домена: ${event.isDomainOwner ? "Да" : "Нет"}\n'
      'Текущий голод: ${currentProfile.hunger}\n'
      'Позиция: ${event.position.latitude}, ${event.position.longitude}',
    );

    // Проверяем, что голод > 0
    if (currentProfile.hunger <= 0) {
      final message = '❌ Охота отменена: голод уже утолён';
      await sendDebugToTelegram(message);
      emit(const ViolationsError('Ваш голод утолён, охотиться незачем.'));
      return;
    }

    final newHunger = currentProfile.hunger - 1;
    // Гарантируем, что голод не станет отрицательным
    final clampedHunger = newHunger > 0 ? newHunger : 0;
    await repository.updateHunger(currentProfile.id, clampedHunger);

    final violationProbability = event.isDomainOwner ? 0.25 : 0.5;
    final violationOccurs = _random.nextDouble() < violationProbability;

    String huntResultMessage = '✅ Охота успешна! Восстановлен 1 пункт голода';
    String violationMessage = '';
    int costToClose = 0;

    if (violationOccurs) {
      costToClose = event.isDomainOwner ? 1 : 2;

      await sendDebugToTelegram(
        '⚠️ Создаем нарушение с параметрами:\n'
        'Violator ID: ${currentProfile.id}\n'
        'Domain ID: ${event.domainId}\n'
        'Cost to close: $costToClose\n'
        'Lat/Lng: ${event.position.latitude}, ${event.position.longitude}',
      );

      await _createViolation(
        description: 'Неосторожная охота',
        hungerSpent: 1,
        latitude: event.position.latitude,
        longitude: event.position.longitude,
        domainId: event.domainId,
        emit: emit, isHunt: true,
      );
    }

    await sendDebugToTelegram(huntResultMessage + violationMessage);
    add(LoadViolations());

    emit(
      HuntCompleted(
        violationOccurred: violationOccurs,
        isDomainOwner: event.isDomainOwner,
        costToClose: violationOccurs ? costToClose : 0,
      ),
    );
  } catch (e) {
    final errorDetails = '❌ Ошибка во время охоты: ${e.toString()}';
    await sendDebugToTelegram(errorDetails);
    emit(ViolationsError(errorDetails));
  }
}

  Future<void> _onCloseViolation(
    CloseViolation event,
    Emitter<MasqueradeState> emit,
  ) async {
    try {
      await sendDebugToTelegram(
        '🔒 Закрытие нарушения\n'
        'ID нарушения: ${event.violationId}\n'
        'Игрок: ${currentProfile.characterName}',
      );
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
      final domainInfluence = domain.totalInfluence;
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

      add(LoadViolations());
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
      await sendDebugToTelegram(
        '👤 Раскрытие нарушителя\n'
        'ID нарушения: ${event.violationId}\n'
        'Игрок: ${currentProfile.characterName}',
      );
      final violation = await repository.getViolationById(event.violationId);
      if (violation == null || !violation.canBeRevealed) {
        emit(ViolationsError('Нарушитель уже раскрыт или невозможно раскрыть'));
        return;
      }

      if (!violation.canBeRevealed) {
        emit(ViolationsError('Слишком поздно раскрывать нарушителя'));
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
      final domainInfluence = domain.totalInfluence;
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

      add(LoadViolations());
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
    required bool isHunt, // Определяет тип нарушения (охота/ручное)
    required Emitter<MasqueradeState> emit,
  }) async {
    final id = _uuid.v4();

    await sendDebugToTelegram(
      '🚨 Нарушение маскарада\n'
      'Игрок: ${currentProfile.characterName} (${currentProfile.id})\n'
      'Описание: $description\n'
      'Голод: $hungerSpent\n'
      'Тип: ${isHunt ? "Охота" : "Ручное"}\n'
      'Домен: $domainId\n'
      'Координаты: $latitude, $longitude',
    );

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

    // Только для ручных нарушений увеличиваем голод
    if (!isHunt) {
      final newHunger = currentProfile.hunger + hungerSpent;
      final updatedProfile = await repository.updateHunger(
        currentProfile.id,
        newHunger,
      );
      if (updatedProfile != null) {
        profileBloc.add(UpdateProfile(updatedProfile));
      }
    }

    add(LoadViolations());
    emit(ViolationReportedSuccessfully());
  }
}
