import 'dart:async';

import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/violation_model.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../services/supabase_service.dart';

class SupabaseRepository {
  final SupabaseService service;
  SupabaseClient get client => _client;
  final SupabaseClient _client;
  final _profileController = StreamController<ProfileModel?>.broadcast();
  ProfileModel? _lastProfile;
  Stream<List<DomainModel>>? _domainsStream;

  SupabaseRepository(this.service) : _client = service.client;
  Stream<ProfileModel?> get profileStream => _profileController.stream;

  Future<ProfileModel?> getCurrentProfile() async {
    {
      final user = client.auth.currentUser;
      if (user == null) {
        sendTelegramMode(chatId: '369397714', message: '❗️ No authenticated user', mode: 'debug');
        return null;
      }

      sendTelegramMode(chatId: '369397714', message: '🔍 Loading current profile for user: ${user.id}', mode: 'debug');
      final profile = await getProfileById(user.id);

      if (profile == null) {
        sendTelegramMode(chatId: '369397714', message: '❌ Profile not found for user: ${user.id}', mode: 'debug');
      } else {
        sendTelegramMode(chatId: '369397714', message: '✅ Current profile loaded: ${profile.characterName}', mode: 'debug');
      }

      return profile;
    }
  }
  
  Future<ProfileModel?> getProfileByLoginCode(
    String code,
    void Function(String msg) debug,
  ) {
    return service.getProfileByLoginCode(code, debug);
  }

  Future<ProfileModel?> getProfileByTelegram(
    String username, {
    void Function(String)? debug,
  }) {
    return service.getProfileByTelegram(username, debug: debug);
  }

  Future<ProfileModel?> updateProfile(ProfileModel profile) async {
    return service.updateProfile(profile);
  }

  Future<void> createProfile(ProfileModel profile) async {
  final updatedProfile = profile.copyWith(
    disciplines: ['Регенерация', 'Прочее'] + profile.disciplines,
  );
  
  return service.createProfile(updatedProfile);
}

  Future<List<DomainModel>> getDomains() {
    return service.getDomains();
  }

  Future<void> transferDomain(String domainId, String newOwnerId) async {
  await service.transferDomain(domainId, newOwnerId);
}

  Future<String?> reportViolation(ViolationModel violation) {
    return service.reportViolation(violation);
  }

  Future<void> closeViolation(String violationId, String resolvedBy) {
    return service.closeViolation(violationId, resolvedBy);
  }

  Future<void> revealViolator(String violationId) {
    return service.revealViolator(violationId);
  }

  Future<Map<String, dynamic>> hunt(String hunterId, String targetId) {
    return service.hunt(hunterId, targetId);
  }

  Future<void> transferHunger({
    required String fromUserId,
    required String toUserId,
    required int amount,
  }) {
    return service.transferHunger(
      fromUserId: fromUserId,
      toUserId: toUserId,
      amount: amount,
    );
  }

  Future<List<ViolationModel>> getViolations() {
    return service.getViolations();
  }

  Future<List<ViolationModel>> getViolationsByDomainId(int domainId) {
    return service.getViolationsByDomainId(domainId);
  }

  Future<ViolationModel?> getViolationById(String id) {
    return service.getViolationById(id);
  }

  @override
  Future<DomainModel?> getDomainById(int id) async {
    return service.getDomainById(id);
  }

  Future<void> createViolation(ViolationModel violation) {
    return service.createViolation(violation);
  }

  Future<int?> updateHunger(String profileId, int hunger) async {
  try {
    await client
        .from('profiles')
        .update({'hunger': hunger})
        .eq('id', profileId);

    sendTelegramMode(chatId: '369397714', message: '✅ Голод обновлён для $profileId: $hunger', mode: 'debug');
    return hunger;
  } catch (e, stack) {
    final errorMsg = '❌ Ошибка обновления голода: $e\n$stack';
    sendTelegramMode(chatId: '369397714', message: errorMsg, mode: 'debug');
    return null;
  }
}

  Future<void> revealViolation({
    required String id,
    required String violatorName,
    required String revealedAt,
  }) {
    return service.revealViolation(
      id: id,
      violatorName: violatorName,
      revealedAt: revealedAt,
    );
  }

  Future<List<ProfileModel>> getAllProfiles() {
    return service.getAllProfiles();
  }

  Future<void> updateInfluence(String profileId, int influence) {
    return service.updateInfluence(profileId, influence);
  }

  Future<ProfileModel?> getProfileById(String id) async {
  try {
    sendTelegramMode(chatId: '369397714', message: '🔍 Запрос профиля по ID: $id', mode: 'debug');
    final response = await client
        .from('profiles')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      sendTelegramMode(chatId: '369397714', message: '❌ Профиль $id не найден', mode: 'debug');
      return null;
    }

    final profile = ProfileModel.fromJson(response);
    sendTelegramMode(chatId: '369397714', message: '✅ Профиль получен: ${profile.characterName}', mode: 'debug');
    return profile;
  } catch (e) {
    sendTelegramMode(chatId: '369397714', message: '❌ Ошибка получения профиля: $e', mode: 'debug');
    return null;
  }
}

  Future<void> updateDomainInfluence(int domainId, int newInfluence) async {
    await service.updateDomainInfluence(domainId, newInfluence);
  }

  void dispose() {
    _profileController.close();
  }

  Future<ProfileModel?> updatePillars(String profileId, List<Map<String, dynamic>> pillars) async {
    final updated = await client
        .from('profiles')
        .update({'pillars': pillars, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', profileId)
        .select()
        .maybeSingle();
    return updated == null ? null : ProfileModel.fromJson(updated);
  }

  Future<void> updateDomainSecurity(int domainId, int newSecurity) async {
  await service.updateDomainSecurity(domainId, newSecurity);
}

  Future<void> setDomainNeutral(int domainId) async {
  await service.setDomainNeutral(domainId);
}

  Future<void> updateDomainMaxSecurity(int domainId, int newMaxSecurity) async {
  await service.updateDomainMaxSecurity(domainId, newMaxSecurity);
}

Future<void> incrementDomainViolationsCount(int domainId) async {
  await service.incrementDomainViolationsCount(domainId);
}

Future<void> updateDomainInfluenceLevel(int domainId, int newInfluence) async {
  await service.updateDomainInfluenceLevel(domainId, newInfluence);
}

Future<void> updateDomainSecurityAndInfluence(int domainId, int newSecurity, int newInfluence) async {
  await service.updateDomainSecurityAndInfluence(domainId, newSecurity, newInfluence);
}

Future<void> updateDomainMaxSecurityAndInfluence(int domainId, int newMaxSecurity, int newInfluence) async {
  await service.updateDomainMaxSecurityAndInfluence(domainId, newMaxSecurity, newInfluence);
}

Future<void> updateDomainBaseIncome(int domainId, int newBaseIncome) async {
  await service.updateDomainBaseIncome(domainId, newBaseIncome);
}

void subscribeToProfileChanges(void Function(ProfileModel) callback) {
  final channel = client.channel('profiles_changes');
  
  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'profiles',
    callback: (payload) {
      if (payload.newRecord != null) {
        final profile = ProfileModel.fromJson(payload.newRecord);
        callback(profile);
      }
    },
  ).subscribe();
}

Future<Map<String, dynamic>?> transferHungerFromDomain(
  int domainId, 
  String targetPlayerId,  // ID уже является строкой
  int amount
) async {
  try {
    final result = await client.rpc('transfer_hunger_from_domain', params: {
      'domain_id': domainId,
      'target_player_id': targetPlayerId,
      'amount': amount,
    });
    
    return result as Map<String, dynamic>?;
  } catch (e) {
    return null;
  }
}

Future<void> forceDomainNeutralization(int domainId) async {
  await service.forceDomainNeutralization(domainId);
}

Future<void> setDomainNeutralFlag(int domainId, bool isNeutral) async {
  await service.setDomainNeutralFlag(domainId, isNeutral);
}

Future<void> updateFcmToken(String userId, String fcmToken) async {
  {
    await client
      .from('profiles')
      .update({
        'fcm_token': fcmToken,
        'updated_at': DateTime.now().toIso8601String(),
      })
      .eq('id', userId);
    
  } 
}

Future<void> saveTelegramChatId(String userId, String chatId, String username) async {
  try {
    await client.from('telegram_subscriptions').upsert({
      'user_id': userId,
      'telegram_chat_id': chatId,
      'username': username,
      'created_at': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    rethrow;
  }
}

Future<List<ProfileModel>> getMalkaviansWithTelegram() async {
  try {
    final response = await client
        .from('profiles')
        .select()
        .eq('clan', 'Малкавиан')
        .not('telegram_chat_id', 'is', null);

    return response
        .map((item) => ProfileModel.fromJson(item))
        .toList();
  } catch (e) {
    return [];
  }
}

Future<List<Map<String, dynamic>>> getMalkavianTelegramChats() async {
  try {
    final response = await client
        .from('telegram_subscriptions')
        .select('''
          telegram_chat_id,
          profiles:user_id (
            clan,
            external_name
          )
        ''')
        .eq('profiles.clan', 'Малкавиан');

    return response;
  } catch (e) {
    return [];
  }
}

Future<List<String>> getMalkavianUsernames() async {
  try {
    final response = await client
        .from('profiles')
        .select('external_name')
        .eq('clan', 'Малкавиан')
        .not('external_name', 'is', null);

    return response
        .map((item) => item['external_name'] as String)
        .toList();
  } catch (e) {
    return [];
  }
}

Future<List<ProfileModel>> getMalkavianProfiles() async {
  try {
    final response = await client
        .from('profiles')
        .select()
        .eq('clan', 'Малкавиан');

    return response
        .map((item) => ProfileModel.fromJson(item))
        .toList();
  } catch (e) {
    return [];
  }
}

// Добавляем метод для получения FCM токена пользователя
Future<String?> getFcmToken(String userId) async {
  try {
    final response = await client
        .from('profiles')
        .select('fcm_token')
        .eq('id', userId)
        .single();
    
    return response['fcm_token'] as String?;
  } catch (e) {
    return null;
  }
}

void subscribeToDomainChanges(void Function(List<DomainModel>) callback) {
  final channel = client.channel('domain_changes');

  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'domains',
    callback: (payload) {
      getDomains().then(callback).catchError((e) {
      });
    },
  ).subscribe();
}

// Добавьте метод для получения FCM токенов Малкавиан
Future<List<String>> getMalkavianFcmTokens() async {
  try {
    final response = await client
      .from('profiles')
      .select('fcm_token')
      .eq('clan', 'Малкавиан')
      .not('fcm_token', 'is', null);
    
    final tokens = response
      .map((profile) => profile['fcm_token'] as String)
      .where((token) => token.isNotEmpty)
      .toList();
        return tokens;
  } catch (e) {
    return [];
  }
}

Stream<List<DomainModel>> get domainsStream {
    if (_domainsStream != null) return _domainsStream!;

    final controller = StreamController<List<DomainModel>>();
    final channel = client.channel('domain_changes');
    final subscription = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'domains',
      callback: (payload) {
        getDomains().then((domains) {
          controller.add(domains);
        }).catchError((e) {
        });
      },
    ).subscribe();

    _domainsStream = controller.stream;
    controller.onCancel = () {
      subscription.unsubscribe();
      _domainsStream = null;
    };

    return _domainsStream!;
  }

  Stream<ProfileModel> profileChanges(String profileId) {
    final controller = StreamController<ProfileModel>();
    final channel = client.channel('profile_changes_$profileId');
    final subscription = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'profiles',
      callback: (payload) {
        if (payload.newRecord['id'] == profileId) {
          getProfileById(profileId).then((profile) {
            if (profile != null) {
              controller.add(profile);
            }
          }).catchError((e) {
            sendTelegramMode(chatId: '369397714', message: '❌ Ошибка загрузки профиля после изменения: $e', mode: 'debug');
          });
        }
      },
    ).subscribe();

    controller.onCancel = () {
      subscription.unsubscribe();
    };

    return controller.stream;
  }
}