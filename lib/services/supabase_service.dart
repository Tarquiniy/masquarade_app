import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/standalone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/profile_model.dart';
import '../models/domain_model.dart';
import '../models/violation_model.dart';

class SupabaseService {
  final SupabaseClient client;
  SupabaseService(this.client);

  Future<ProfileModel?> getProfileByLoginCode(
    String code,
    void Function(String)? debug,
  ) async {
    final normalized = code.trim().toUpperCase();
    debug?.call('[DEBUG AUTH] Получен код: $normalized');

    final List<Map<String, dynamic>> codes = await client
        .from('login_codes')
        .select()
        .eq('code', normalized)
        .limit(1);

    if (codes.isEmpty) {
      debug?.call('[DEBUG AUTH] ❌ Код не найден в таблице login_codes');
      return null;
    }

    final entry = codes.first;
    final expiresAtRaw = entry['expires_at'] as String?;
    final telegramUsername = entry['external_name'] as String?;

    if (telegramUsername == null) {
      debug?.call('[DEBUG AUTH] ❌ Не указан external_name');
      return null;
    }

    final expiresAt = DateTime.tryParse(expiresAtRaw ?? '');
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      debug?.call('[DEBUG AUTH] ⚠️ Код просрочен: $expiresAt');
      return null;
    }

    debug?.call('[DEBUG AUTH] ✅ Код действителен, username: $telegramUsername');
    final profileRow = await client
        .from('predefined_profiles')
        .select()
        .eq('external_name', telegramUsername)
        .maybeSingle();

    if (profileRow == null) {
      debug?.call('[DEBUG AUTH] ❌ Профиль не найден по telegram_username');
      return null;
    }

    debug?.call('[DEBUG AUTH] ✅ Профиль найден: ${profileRow.toString()}');
    return ProfileModel(
    id: telegramUsername,
    characterName: profileRow['character_name'],
    sect: profileRow['sect'],
    clan: profileRow['clan'],
    humanity: profileRow['humanity'],
    disciplines: List<String>.from(profileRow['disciplines'] ?? []),
    bloodPower: profileRow['blood_power'] ?? 0,
    hunger: 0,
    domainIds: [],
    role: 'player',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    pillars: [], 
    generation: profileRow['generation'] ?? 13,
  );
  }

  Future<ProfileModel?> getProfileByTelegram(
    String username, {
    void Function(String)? debug,
  }) async {
    try {
      debug?.call('🔍 Поиск профиля по Telegram: @$username');

      // Нормализуем username (убираем @ в начале если есть)
      final normalizedUsername = username.startsWith('@') 
          ? username.substring(1) 
          : username;

      debug?.call('📝 Нормализованный username: $normalizedUsername');

      // Сначала ищем в таблице profiles
      var response = await client
          .from('profiles')
          .select()
          .ilike('external_name', normalizedUsername)
          .maybeSingle();

      if (response != null) {
        debug?.call('✅ Найден существующий профиль в таблице profiles');
        return ProfileModel.fromJson(response);
      }

      debug?.call('🔍 Поиск в predefined_profiles: @$normalizedUsername');
      
      // Ищем в predefined_profiles
      final predefinedResponse = await client
          .from('predefined_profiles')
          .select()
          .ilike('external_name', normalizedUsername)
          .maybeSingle();

      if (predefinedResponse != null) {
        debug?.call('✅ Найден predefined профиль, создаем новый профиль');

        // Генерируем новый ID на основе максимального существующего ID
        final maxIdResponse = await client
            .from('profiles')
            .select('id')
            .order('id', ascending: false)
            .limit(1)
            .maybeSingle();

        int newId = 1;
        if (maxIdResponse != null && maxIdResponse['id'] != null) {
          try {
            final maxId = int.parse(maxIdResponse['id'].toString());
            newId = maxId + 1;
          } catch (e) {
            debug?.call('⚠️ Ошибка парсинга максимального ID, начинаем с 1');
          }
        }

        debug?.call('🆕 Сгенерирован новый ID: $newId');

        // Создаем новый профиль на основе predefined_profiles
        final newProfile = ProfileModel(
          id: newId.toString(), // Используем сгенерированный ID
          characterName: predefinedResponse['character_name'] ?? 'Безымянный',
          sect: predefinedResponse['sect'] ?? 'Неизвестно',
          clan: predefinedResponse['clan'] ?? 'Неизвестно',
          humanity: predefinedResponse['humanity'] ?? 0,
          disciplines: List<String>.from(predefinedResponse['disciplines'] ?? []),
          bloodPower: predefinedResponse['blood_power'] ?? 0,
          hunger: predefinedResponse['hunger'] ?? 0,
          domainIds: List<int>.from(predefinedResponse['domain_ids'] ?? []),
          role: predefinedResponse['role'] ?? 'user',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          external_name: normalizedUsername,
          adminInfluence: predefinedResponse['admin_influence'] ?? 0,
          pillars: List<Map<String, dynamic>>.from(predefinedResponse['pillars'] ?? []), 
          generation: predefinedResponse['generation'] ?? 13,
        );

        // Вставляем новый профиль
        final insertResponse = await client
            .from('profiles')
            .insert(newProfile.toJson())
            .select()
            .single();

        debug?.call('✅ Профиль создан успешно');
        return ProfileModel.fromJson(insertResponse);
      }

      debug?.call('❌ Профиль не найден ни в profiles, ни в predefined_profiles');
      return null;
    } catch (e, stackTrace) {
      debug?.call('❌ Ошибка при поиске профиля: $e\n$stackTrace');
      return null;
    }
  }

  // --- DOMAINS ---
  Future<List<DomainModel>> getDomains() async {
    try {
      final data = await client.from('domains').select();
      return (data as List).map((e) => DomainModel.fromJson(e)).toList();
    } catch (e) {
      final errorMsg = '❌ Ошибка загрузки доменов: ${e.toString()}';
      print(errorMsg);
      await sendDebugToTelegram(errorMsg);
      rethrow;
    }
  }

  Future<void> transferDomain(String domainId, String newOwnerId) async {
  try {
    // 1. Получаем текущего владельца домена
    final domainData = await client
        .from('domains')
        .select('ownerId')
        .eq('id', int.parse(domainId))
        .single();

    final oldOwnerId = domainData['ownerId'] as String?;

    // 2. Обновляем домен: устанавливаем нового владельца и снимаем нейтральный статус
    await client
        .from('domains')
        .update({ 
          'ownerId': newOwnerId,
          'isNeutral': false 
        })
        .eq('id', int.parse(domainId));

    // 3. Обновляем профиль старого владельца (удаляем домен из domain_ids)
    if (oldOwnerId != null && oldOwnerId.isNotEmpty) {
      final oldOwnerData = await client
          .from('profiles')
          .select('domain_ids')
          .eq('id', oldOwnerId)
          .single();

      List<int> oldDomainIds = List<int>.from(oldOwnerData['domain_ids'] ?? []);
      oldDomainIds.remove(int.parse(domainId));

      await client
          .from('profiles')
          .update({ 'domain_ids': oldDomainIds })
          .eq('id', oldOwnerId);
    }

    // 4. Обновляем профиль нового владельца (добавляем домен в domain_ids)
    final newOwnerData = await client
        .from('profiles')
        .select('domain_ids')
        .eq('id', newOwnerId)
        .single();

    List<int> newDomainIds = List<int>.from(newOwnerData['domain_ids'] ?? []);
    if (!newDomainIds.contains(int.parse(domainId))) {
      newDomainIds.add(int.parse(domainId));
    }

    await client
        .from('profiles')
        .update({ 'domain_ids': newDomainIds })
        .eq('id', newOwnerId);

    sendDebugToTelegram('✅ Домен $domainId передан от $oldOwnerId к $newOwnerId');
  } catch (e, stack) {
    final errorMsg = '❌ Ошибка передачи домена: $e\n$stack';
    sendDebugToTelegram(errorMsg);
    rethrow;
  }
}

  Future<ProfileModel?> updatePillars(String profileId, List<Map<String, dynamic>> pillars) async {
  // Рассчитываем новую человечность
  int newHumanity = pillars.length;

  final updated = await client
      .from('profiles')
      .update({
        'pillars': pillars,
        'humanity': newHumanity, // Обновляем человечность
        'updated_at': DateTime.now().toIso8601String(),
      })
      .eq('id', profileId)
      .select()
      .maybeSingle();
  return updated == null ? null : ProfileModel.fromJson(updated);
}

  Future<List<ViolationModel>> getViolations() async {
  try {
    sendDebugToTelegram('⚡️ SQL: SELECT * FROM violations');
    final data = await client.from('violations').select();

    await sendDebugToTelegram(
      '✅ Получено нарушений: ${data.length}\n'
      'Первые 3: ${data.take(3).map((v) => v['id']).join(', ')}'
    );

    return (data as List).map((e) => ViolationModel.fromJson(e)).toList();
  } catch (e) {
    final errorMsg = '❌ Ошибка загрузки нарушений: ${e.toString()}';
    print(errorMsg);
    await sendDebugToTelegram(errorMsg);
    rethrow;
  }
  }



  Future<List<ViolationModel>> getViolationsByDomainId(int domainId) async {
  await sendDebugToTelegram('🔍 SQL: SELECT * FROM violations WHERE domain_id = $domainId ORDER BY created_at DESC');

  final response = await client
      .from('violations')
      .select()
      .eq('domain_id', domainId)
      .order('created_at', ascending: false);

  await sendDebugToTelegram('📥 Ответ Supabase: $response');

  final list = (response as List)
      .map((json) => ViolationModel.fromJson(json))
      .toList();

  return list;
}

  Future<ViolationModel?> getViolationById(String id) async {
    final data = await client
        .from('violations')
        .select()
        .eq('id', id)
        .maybeSingle();
    return data == null ? null : ViolationModel.fromJson(data);
  }

  Future<DomainModel?> getDomainById(int id) async {
    try {
      final data =
          await client.from('domains').select().eq('id', id).maybeSingle();
      return data == null ? null : DomainModel.fromJson(data);
    } catch (e) {
      final errorMsg = '❌ Ошибка поиска домена $id: ${e.toString()}';
      print(errorMsg);
      await sendDebugToTelegram(errorMsg);
      return null;
    }
  }

Future<void> createViolation(ViolationModel violation) async {
  try {
    final json = violation.toJson();
    json.remove('id');

    await sendDebugToTelegram(
      '💾 Сохранение нарушения в БД:\n'
      '• Domain ID: ${violation.domainId}\n'
      '• Description: ${violation.description}\n'
      '• Coordinates: ${violation.latitude}, ${violation.longitude}\n'
      '• JSON: $json'
    );

    await client.from('violations').insert(json);
    await sendDebugToTelegram('✅ Нарушение успешно сохранено в БД');
  } catch (e, stack) {
    await sendDebugToTelegram('❌ Ошибка сохранения нарушения: $e\n$stack');
    rethrow;
  }
}

  Future<String?> reportViolation(ViolationModel violation) async {
    final json = violation.toJson();
    final inserted = await client
        .from('violations')
        .insert(json)
        .select()
        .maybeSingle();
    return inserted == null ? null : (inserted['id'] as String?);
  }

  Future<void> closeViolation(String violationId, String resolvedBy) async {
    await client
        .from('violations')
        .update({
          'status': 'closed',
          'closed_at': DateTime.now().toIso8601String(),
          'resolved_by': resolvedBy,
        })
        .eq('id', violationId);
  }

  Future<void> revealViolator(String violationId) async {
    await client
        .from('violations')
        .update({'revealed': true})
        .eq('id', violationId);
  }

  Future<void> revealViolation({
    required String id,
    required String violatorName,
    required String revealedAt,
  }) async {
    await client
        .from('violations')
        .update({
          'status': 'revealed',
          'violator_name': violatorName,
          'revealed_at': revealedAt,
        })
        .eq('id', id);
  }

  Future<Map<String, dynamic>> hunt(String hunterId, String targetId) async {
    final result = await client
        .rpc(
          'perform_hunt',
          params: {'hunter_id': hunterId, 'target_id': targetId},
        )
        .select()
        .maybeSingle();
    return result ?? {};
  }

  Future<void> transferHunger({
    required String fromUserId,
    required String toUserId,
    required int amount,
  }) async {
    await client.rpc(
      'transfer_hunger',
      params: {
        'from_user_id': fromUserId,
        'to_user_id': toUserId,
        'amount': amount,
      },
    );
  }

  Future<ProfileModel?> getProfileById(String id) async {
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return ProfileModel.fromJson(response);
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка получения профиля: $e');
      return null;
    }
  }

  Future<List<ProfileModel>> getAllProfiles() async {
    final data = await client.from('profiles').select();
    return (data as List).map((e) => ProfileModel.fromJson(e)).toList();
  }

  Future<int?> updateHunger(String profileId, int hunger) async {
  try {
    await client
        .from('profiles')
        .update({'hunger': hunger})
        .eq('id', profileId);
    return hunger;
  } catch (e, stack) {
    final errorMsg = '❌ SupabaseService: Ошибка обновления голода: $e\n$stack';
    sendDebugToTelegram(errorMsg);
    return null;
  }
}

  Future<void> updateInfluence(String profileId, int influence) async {
    await client.from('profiles').update({'admin_influence': influence}).eq('id', profileId);
  }

  Future<void> updateDomainInfluence(int domainId, int newInfluence) async {
    await client.from('domains').update({'admin_influence': newInfluence}).eq('id', domainId);
  }


  Future<void> createProfile(ProfileModel profile) async {
    await client.from('profiles').insert(profile.toJson());
  }

  Future<ProfileModel?> updateProfile(ProfileModel profile) async {
    try {
      // Формируем данные для обновления
      final updateData = {
        'humanity': profile.humanity,
        'pillars': profile.pillars,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Выполняем обновление
      final response = await client
          .from('profiles')
          .update(updateData)
          .eq('id', profile.id)
          .select();

      if (response.isEmpty) return null;

      return ProfileModel.fromJson(response.first);
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка обновления профиля: $e');
      return null;
    }
  }

  Future<void> updateDomainSecurity(int domainId, int newSecurity) async {
  try {
    sendDebugToTelegram('🛡️ Обновление защиты домена $domainId на $newSecurity');

    // Обновляем защиту
    await client
        .from('domains')
        .update({'securityLevel': newSecurity})
        .eq('id', domainId);

    sendDebugToTelegram('✅ Защита домена $domainId обновлена на $newSecurity');

    // Если защита стала 0, устанавливаем флаг isNeutral
    if (newSecurity == 0) {
      sendDebugToTelegram('🔄 Защита стала 0, устанавливаем isNeutral=true');
      await setDomainNeutralFlag(domainId, true);
      
      // Также очищаем владельца домена, используя NULL
      await client
          .from('domains')
          .update({'ownerId': null})  // Используем NULL вместо пустой строки
          .eq('id', domainId);
          
      sendDebugToTelegram('✅ Владелец домена $domainId очищен (установлен в NULL)');
    }
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка обновления защиты домена $domainId: $e');
    rethrow;
  }
}

Future<void> setDomainNeutral(int domainId) async {
  try {
    sendDebugToTelegram('🔄 Нейтрализация домена $domainId');

    // Получаем текущего владельца домена
    final domainData = await client
        .from('domains')
        .select('ownerId')
        .eq('id', domainId)
        .single();

    final ownerId = domainData['ownerId'] as String?;

    // Обновляем домен: делаем нейтральным и сбрасываем владельца
    await client
        .from('domains')
        .update({
          'isNeutral': true,
          'ownerId': '',
        })
        .eq('id', domainId);

    sendDebugToTelegram('✅ Домен $domainId помечен как нейтральный');

    // Если у домена был владелец, убираем domainId из его domain_ids
    if (ownerId != null && ownerId.isNotEmpty) {
      final profileData = await client
          .from('profiles')
          .select('domain_ids')
          .eq('id', ownerId)
          .single();

      List<int> domainIds = List<int>.from(profileData['domain_ids'] ?? []);
      if (domainIds.contains(domainId)) {
        domainIds.remove(domainId);
        
        await client
            .from('profiles')
            .update({'domain_ids': domainIds})
            .eq('id', ownerId);

        sendDebugToTelegram('✅ Домен $domainId удален из списка владельца $ownerId');
      }
    }
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка при нейтрализации домена $domainId: $e');
    rethrow;
  }
}

Future<void> updateDomainMaxSecurity(int domainId, int newMaxSecurity) async {
  await client.from('domains').update({
    'max_security_level': newMaxSecurity,
    'updated_at': DateTime.now().toIso8601String(),
  }).eq('id', domainId);
}

Future<void> incrementDomainViolationsCount(int domainId) async {
  // Получаем текущее количество нарушений
  final domain = await getDomainById(domainId);
  if (domain != null) {
    final newViolationsCount = domain.openViolationsCount + 1;
    
    // Обновляем счетчик нарушений
    await client.from('domains').update({
      'open_violations_count': newViolationsCount,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', domainId);
  }
}

Future<void> updateDomainInfluenceLevel(int domainId, int newInfluence) async {
  try {
    // Простое обновление без сложной логики
    await client.from('domains').update({
      'influenceLevel': newInfluence,
    }).eq('id', domainId);
  } catch (e) {
    rethrow;
  }
}

Future<void> forceDomainNeutralization(int domainId) async {
  try {
    sendDebugToTelegram('🔄 Принудительная нейтрализация домена $domainId');

    // Получаем текущего владельца домена
    final domainData = await client
        .from('domains')
        .select('ownerId, name')
        .eq('id', domainId)
        .single();

    final ownerId = domainData['ownerId'] as String?;
    final domainName = domainData['name'] as String? ?? 'Неизвестный домен';

    // Немедленно устанавливаем домен как нейтральный
    await client
        .from('domains')
        .update({
          'isNeutral': true,
          'ownerId': null,
          'securityLevel': 0,
        })
        .eq('id', domainId);

    sendDebugToTelegram('✅ Домен $domainId принудительно помечен как нейтральный');

    // Если у домена был владелец, убираем domainId из его domain_ids
    if (ownerId != null && ownerId.isNotEmpty) {
      final profileData = await client
          .from('profiles')
          .select('domain_ids')
          .eq('id', ownerId)
          .single();

      List<int> domainIds = List<int>.from(profileData['domain_ids'] ?? []);
      if (domainIds.contains(domainId)) {
        domainIds.remove(domainId);
        
        await client
            .from('profiles')
            .update({'domain_ids': domainIds})
            .eq('id', ownerId);

        sendDebugToTelegram('✅ Домен $domainId удален из списка владельца $ownerId');
        
        // Отправляем уведомление
        await sendDomainNeutralizedNotification(ownerId, domainName, domainId);
      }
    }
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка при принудительной нейтрализации домена $domainId: $e');
    rethrow;
  }
}

Future<void> updateDomainSecurityAndInfluence(int domainId, int newSecurity, int newInfluence) async {
  try {
    sendDebugToTelegram('🔄 Обновление защиты и влияния домена $domainId: защита=$newSecurity, влияние=$newInfluence');

    // Обновляем защиту и влияние
    await client
        .from('domains')
        .update({
          'securityLevel': newSecurity,
          'influenceLevel': newInfluence,
        })
        .eq('id', domainId);

    sendDebugToTelegram('✅ Защита и влияние домена $domainId обновлены');

    // Если защита стала 0, вызываем принудительную нейтрализацию
    if (newSecurity == 0) {
      sendDebugToTelegram('🔄 Защита стала 0, запускаем принудительную нейтрализацию');
      await forceDomainNeutralization(domainId);
    }
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка обновления защиты и влияния домена $domainId: $e');
    rethrow;
  }
}

Future<void> updateDomainMaxSecurityAndInfluence(int domainId, int newMaxSecurity, int newInfluence) async {
  try {
    sendDebugToTelegram('🔄 Атомарное обновление макс. защиты и влияния домена $domainId: макс. защита=$newMaxSecurity, влияние=$newInfluence');
    
    // Используем транзакцию для атомарного обновления
    final response = await client.from('domains').update({
      'max_security_level': newMaxSecurity,
      'influenceLevel': newInfluence,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', domainId);
    
    if (response.error != null) {
      throw Exception('Supabase error: ${response.error.message}');
    }
    
    sendDebugToTelegram('✅ Атомарное обновление макс. защиты завершено: домен $domainId');
  } catch (e, stack) {
    final errorMsg = '❌ Ошибка атомарного обновления макс. защиты домена $domainId: ${e.toString()}\n${stack.toString()}';
    sendDebugToTelegram(errorMsg);
    rethrow;
  }
}

Future<void> updateDomainBaseIncome(int domainId, int newBaseIncome) async {
  await client
      .from('domains')
      .update({'base_income': newBaseIncome})
      .eq('id', domainId);
}

Future<void> setDomainNeutralFlag(int domainId, bool isNeutral) async {
  try {
    sendDebugToTelegram('🔄 Установка флага isNeutral=$isNeutral для домена $domainId');

    await client
        .from('domains')
        .update({
          'isNeutral': isNeutral,
          'ownerId': isNeutral ? null : '', // Для нейтральных доменов используем NULL
        })
        .eq('id', domainId);

    sendDebugToTelegram('✅ Флаг isNeutral=$isNeutral установлен для домена $domainId');
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка установки флага isNeutral для домена $domainId: $e');
    rethrow;
  }
}

Future<void> sendDomainNeutralizedNotification(String userId, String domainName, int domainId) async {
  try {
    // Вызываем Supabase Edge Function для отправки уведомления
    final response = await client.rpc('send_push_notification', params: {
      'user_id': userId,
      'title': 'Домен стал нейтральным',
      'message': 'Домен "$domainName" стал нейтральным из-за нулевой защиты',
      'data': {
        'type': 'domain_neutralized',
        'domain_id': domainId,
        'domain_name': domainName,
      }
    });

    sendDebugToTelegram('✅ Уведомление отправлено пользователю $userId о домене $domainName');
  } catch (e) {
    sendDebugToTelegram('❌ Ошибка отправки уведомления: $e');
  }
}

}