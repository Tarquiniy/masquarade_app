import 'dart:io';
import 'dart:typed_data';

import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
        .eq('telegram_username', telegramUsername)
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
      status: profileRow['status'],
      disciplines: List<String>.from(profileRow['disciplines']),
      bloodPower: profileRow['blood_power'],
      hunger: 0,
      domainIds: [],
      role: 'player',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      pillars: [],
    );
  }

  Future<ProfileModel?> getProfileByTelegram(
    String username, {
    void Function(String)? debug,
  }) async {
    final clean = username.trim().replaceFirst('@', '');
    debug?.call('🔎 Ищем профиль по external_name="$clean"');

    try {
      // 1. Сначала пробуем найти в таблице profiles
      var profileData = await client
          .from('profiles')
          .select()
          .eq('telegram_username', clean)
          .maybeSingle();

      if (profileData != null) {
        debug?.call('✅ Профиль найден в таблице profiles');
        return ProfileModel.fromJson(profileData);
      }

      // 2. Если нет в profiles, ищем в predefined_profiles
      profileData = await client
          .from('predefined_profiles')
          .select()
          .eq('external_name', clean)
          .maybeSingle();

      if (profileData == null) {
        debug?.call('❌ Профиль не найден');
        return null;
      }

      // 3. Создаем профиль в таблице profiles
      final predefinedProfile = ProfileModel.fromJson(profileData);
      final newProfile = predefinedProfile.copyWith(
        hunger: 5,
        external_name: clean,
      );

      // Логируем создание профиля
      debug?.call('Создаем новый профиль: ${newProfile.toJson()}');

      final insertResponse = await client
          .from('profiles')
          .insert(newProfile.toJson())
          .select()
          .single();

      debug?.call('✅ Профиль создан: ${insertResponse}');
      return ProfileModel.fromJson(insertResponse);
    } catch (e) {
      debug?.call('❌ Ошибка при запросе: $e');
      return null;
    }
  }

  Future<void> createProfile(ProfileModel profile) async {
    final json = profile.toJson();
    await client.from('profiles').insert(json);
  }

  Future<void> updateProfile(ProfileModel profile) async {
    await client.from('profiles').update(profile.toJson()).eq('id', profile.id);
  }

  Future<List<DomainModel>> getDomains() async {
    try {
      final data = await client.from('domains').select();
      final domains = (data as List)
          .map((e) => DomainModel.fromJson(e))
          .toList();

      // Проверяем наличие нейтральной территории
      final hasNeutral = domains.any((d) => d.isNeutral);

      if (!hasNeutral) {
        await sendDebugToTelegram('⚠️ В базе нет нейтральной территории');
        domains.add(
          DomainModel(
            id: -1, // Специальное значение для нейтрального домена
            name: 'Neutral Territory',
            latitude: 0,
            longitude: 0,
            boundaryPoints: [],
            isNeutral: true,
            ownerId: 'нет',
          ),
        );
      }

      return domains;
    } catch (e) {
      final errorMsg = '❌ Ошибка загрузки доменов: ${e.toString()}';
      print(errorMsg);
      await sendDebugToTelegram(errorMsg);

      // Возвращаем нейтральную территорию как fallback
      return [
        DomainModel(
          id: -1,
          name: 'Neutral Territory',
          latitude: 0,
          longitude: 0,
          boundaryPoints: [],
          isNeutral: true,
          ownerId: 'нет',
        ),
      ];
    }
  }

  Future<void> transferDomain(String domainId, String newOwnerId) async {
    // Обновляем профиль нового владельца
    await client
        .from('profiles')
        .update({'domain_ids': [int.parse(domainId)]}) // Изменено
        .eq('id', newOwnerId);

    // Обновляем профиль старого владельца
    final oldOwner = await client
        .from('domains')
        .select('owner_id')
        .eq('id', domainId)
        .single()
        .then((data) => data['owner_id'] as String?);

    if (oldOwner != null) {
      await client
          .from('profiles')
          .update({'domain_ids': []}) // Изменено
          .eq('id', oldOwner);
    }
  }

  Future<String?> reportViolation(ViolationModel violation) async {
    final json = violation.toJson();
    final inserted = await client
        .from('violations')
        .insert(json)
        .select()
        .single();
    return inserted['id'] as String?;
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

  Future<List<ViolationModel>> getViolations() async {
    try {
      final data = await client.from('violations').select();

      // Логирование количества полученных нарушений
      print('✅ Получено нарушений: ${data.length}');
      await sendDebugToTelegram('✅ Получено нарушений: ${data.length}');

      return (data as List).map((e) => ViolationModel.fromJson(e)).toList();
    } catch (e) {
      final errorMsg = '❌ Ошибка загрузки нарушений: ${e.toString()}';
      print(errorMsg);
      await sendDebugToTelegram(errorMsg);
      rethrow;
    }
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
    if (id == null) {
      print('⚠️ getDomainById вызван с пустым ID');
      await sendDebugToTelegram('⚠️ getDomainById вызван с пустым ID');
      return null;
    }

    try {
      print('🔍 Поиск домена по ID: $id');
      final data = await client
          .from('domains')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (data == null) {
        print('❌ Домен с ID $id не найден');
        await sendDebugToTelegram('❌ Домен с ID $id не найден');
      }

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
        '📝 Финальный JSON для создания нарушения:\n$json',
      );

      await client.from('violations').insert(json);
    } catch (e, stack) {
      await sendDebugToTelegram('❌ Ошибка создания нарушения: $e\n$stack');
      rethrow;
    }
  }

  Future<ProfileModel?> updateHunger(String profileId, int hunger) async {
  try {
    // Гарантируем, что голод не может быть отрицательным
    final clampedHunger = hunger < 0 ? 0 : hunger;

    final response = await client
        .from('profiles')
        .update({'hunger': clampedHunger})
        .eq('id', profileId)
        .select()
        .single();

    return ProfileModel.fromJson(response);
  } catch (e) {
    print('❌ Ошибка обновления голода: $e');
    return null;
  }
}

  Future<void> revealViolation({
    required String id,
    required String violatorName,
    required String revealedAt,
  }) async {
    await client
        .from('violations')
        .update({
          'violator_known': true,
          'violator_name': violatorName,
          'revealed_at': revealedAt,
          'status': 'revealed',
        })
        .eq('id', id);
  }

  Future<void> updateInfluence(String profileId, int influence) async {
    await client
        .from('profiles')
        .update({'influence': influence})
        .eq('id', profileId);
  }

  Future<ProfileModel?> getProfileById(String id) async {
    try {
      print('🔍 Getting profile by ID: $id');
      final data = await client
          .from('profiles')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (data == null) {
        print('❌ Profile not found for ID: $id');
        return null;
      }

      final profile = ProfileModel.fromJson(data);
      print('✅ Profile loaded: ${profile.characterName}');
      return profile;
    } catch (e) {
      print('❌ Error getting profile by ID: $e');
      return null;
    }
  }

  Future<List<ProfileModel>> getAllProfiles() async {
    final data = await client.from('profiles').select();
    return (data as List).map((e) => ProfileModel.fromJson(e)).toList();
  }

  Future<void> checkViolationsTable() async {
    try {
      // Просто запрашиваем одну запись, чтобы проверить доступность таблицы
      final response = await client.from('violations').select().limit(1);
      print('✅ Таблица violations существует');
    } catch (e) {
      print('❌ Таблица violations недоступна: ${e.toString()}');
    }
  }

  Future<ProfileModel?> getCurrentProfile({
    void Function(String)? debug,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        debug?.call('❗ currentUser == null');
        return null;
      }

      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (data == null) {
        debug?.call('❗ Профиль не найден для user.id=${user.id}');
        return null;
      }

      return ProfileModel.fromJson(data);
    } catch (e) {
      debug?.call('❌ Ошибка в getCurrentProfile: $e');
      return null;
    }
  }

  Future<void> updateDomainInfluence(int domainId, int newInfluence) async {
    try {
      await client
          .from('domains')
          .update({'admin_influence': newInfluence})
          .eq('id', domainId);
    } catch (e) {
      print('❌ Ошибка обновления влияния домена: $e');
      rethrow;
    }
  }

  Future<String> uploadMedia(
    Uint8List bytes,
    String fileName,
    {required String fileType}
  ) async {
    try {
      await client.storage
        .from('carpet_chat_media')
        .uploadBinary(
          fileName,
          bytes,
        );

      return client.storage
        .from('carpet_chat_media')
        .getPublicUrl(fileName);
    } catch (e) {
      throw Exception('Ошибка загрузки: $e');
    }
  }

  Future<List<DomainModel>> getUserDomains(String userId) async {
    try {
      final data = await client
          .from('domains')
          .select()
          .eq('owner_id', userId);
      
      return (data as List).map((e) => DomainModel.fromJson(e)).toList();
    } catch (e) {
      sendDebugToTelegram('Ошибка получения доменов пользователя: $e');
      return [];
    }
  }
}