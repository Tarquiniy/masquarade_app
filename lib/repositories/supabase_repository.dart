import '../models/profile_model.dart';
import '../models/violation_model.dart';
import '../models/domain_model.dart';
import '../services/supabase_service.dart';

class SupabaseRepository {
  final SupabaseService service;

  SupabaseRepository(this.service);

  Future<ProfileModel?> getCurrentProfile() {
    return service.getCurrentProfile();
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

  Future<void> updateHunger(String profileId, int hunger) {
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

  Future<ProfileModel?> getProfileById(String id) {
    return service.getProfileById(id);
  }
}
