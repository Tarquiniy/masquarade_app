import 'dart:async';

import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/repositories/supabase_repository.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';

class DomainMonitorService {
  final SupabaseRepository repository;
  List<DomainModel> _previousDomains = [];

  DomainMonitorService(this.repository);

  Future<void> startMonitoring() async {
    // Загружаем初始ные домены
    _previousDomains = await repository.getDomains();
    
    // Подписываемся на изменения
    repository.subscribeToDomainChanges((domains) {
      _handleDomainChanges(domains);
    });
  }

  void _handleDomainChanges(List<DomainModel> newDomains) {
    try {
      // Проверяем изменения isNeutral
      for (final newDomain in newDomains) {
        if (newDomain.isNeutral) {
          final oldDomain = _previousDomains.firstWhere(
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

          // Если домен стал нейтральным
          if (!oldDomain.isNeutral && newDomain.isNeutral && newDomain.ownerId.isNotEmpty) {
            _sendDomainNeutralNotification(newDomain);
          }
        }
      }

      _previousDomains = newDomains;
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка обработки изменений доменов: $e');
    }
  }

  Future<void> _sendDomainNeutralNotification(DomainModel domain) async {
    try {
      final ownerProfile = await repository.getProfileById(domain.ownerId);
      if (ownerProfile == null || ownerProfile.telegramChatId == null) {
        return;
      }

      final message =
        '⚠️ ВАЖНО: Домен "${domain.name}" стал нейтральным!\n'
        'Защита домена упала до 0. Вы больше не контролируете эту территорию.';

      await sendTelegramMessageDirect(ownerProfile.telegramChatId!, message);
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка отправки уведомления: $e');
    }
  }

  void startPeriodicCheck() {
  Timer.periodic(Duration(minutes: 1), (timer) async {
    final currentDomains = await repository.getDomains();
    _handleDomainChanges(currentDomains);
  });
}
}