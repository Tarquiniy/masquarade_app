import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../models/violation_model.dart';
import '../models/domain_model.dart';
import '../services/supabase_service.dart';

class SupabaseRepository {
  final SupabaseService service;
  final SupabaseClient client;
  final _profileController = StreamController<ProfileModel?>.broadcast();

  SupabaseRepository(this.service) : client = service.client;
  Stream<ProfileModel?> get profileStream => _profileController.stream;

  Future<ProfileModel?> getCurrentProfile() async {
    try {
      final user = client.auth.currentUser;
      if (user == null) {
        print('❗️ No authenticated user');
        return null;
      }

      print('🔍 Loading current profile for user: ${user.id}');
      final profile = await getProfileById(user.id);

      if (profile == null) {
        print('❌ Profile not found for user: ${user.id}');
      } else {
        print('✅ Current profile loaded: ${profile.characterName}');
      }

      return profile;
    } catch (e) {
      print('❌ Error getting current profile: $e');
      return null;
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

  Future<void> updateProfile(ProfileModel profile) {
    return service.updateProfile(profile);
  }

  Future<void> createProfile(ProfileModel profile) {
    return service.createProfile(profile);
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

  Future<ProfileModel?> updateHunger(String profileId, int hunger) async {
    return service.updateHunger(profileId, hunger);
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
      final profile = await service.getProfileById(id);
      _profileController.add(profile);
      return profile;
    } catch (e) {
      _profileController.add(null);
      return null;
    }
  }

  // Новый метод для обновления влияния домена
  Future<void> updateDomainInfluence(int domainId, int newInfluence) async {
    await service.updateDomainInfluence(domainId, newInfluence);
  }

  void dispose() {
    _profileController.close();
  }
}
