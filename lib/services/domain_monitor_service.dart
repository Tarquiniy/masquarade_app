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
{
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
    }
  }

  Future<void> _sendDomainNeutralNotification(DomainModel domain) async {
    {
      final ownerProfile = await repository.getProfileById(domain.ownerId);
      if (ownerProfile == null || ownerProfile.telegramChatId == null) {
        return;
      }
   }
  }

  void startPeriodicCheck() {
  Timer.periodic(Duration(minutes: 1), (timer) async {
    final currentDomains = await repository.getDomains();
    _handleDomainChanges(currentDomains);
  });
}
}