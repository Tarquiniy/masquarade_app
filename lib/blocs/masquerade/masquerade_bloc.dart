import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';
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

  MasqueradeBloc({required this.repository, required this.currentProfile})
    : super(ViolationsLoading()) {
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

      if (currentProfile.hunger == 0) {
        final message = '❌ Охота отменена: недостаточно голода';
        await sendDebugToTelegram(message);
        emit(const ViolationsError('Вы слишком голодны для охоты.'));
        return;
      }

      final newHunger = currentProfile.hunger - 1;
      await repository.updateHunger(currentProfile.id, newHunger);

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
          emit: emit,
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
      if (violation == null) {
        emit(ViolationsError('Нарушение не найдено'));
        return;
      }

      final domain = await repository.getDomainById(violation.domainId);
      if (domain == null || domain.ownerId != currentProfile.id) {
        emit(ViolationsError('Вы не владеете этим доменом'));
        return;
      }

      if (currentProfile.influence < violation.costToClose) {
        emit(ViolationsError('Недостаточно влияния для закрытия нарушения'));
        return;
      }

      await repository.closeViolation(violation.id, currentProfile.id);

      final newInfluence = currentProfile.influence - violation.costToClose;
      await repository.updateInfluence(currentProfile.id, newInfluence);

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
      if (violation == null) {
        emit(ViolationsError('Нарушение не найдено'));
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
    required Emitter<MasqueradeState> emit,
  }) async {
    final id = _uuid.v4();

    await sendDebugToTelegram(
      '🚨 Нарушение маскарада\n'
      'Игрок: ${currentProfile.characterName} (${currentProfile.id})\n'
      'Описание: $description\n'
      'Голод: $hungerSpent\n'
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

    final updatedHunger = currentProfile.hunger - hungerSpent;
    await repository.updateHunger(currentProfile.id, updatedHunger);

    add(LoadViolations());
    emit(ViolationReportedSuccessfully());
  }
}
