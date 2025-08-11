import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FirebaseChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final Map<String, String> _nameCache = {};

  Future<void> sendMessage({
    required String senderId,
    required String? text,
    String? mediaUrl,
    String? mediaType,
  }) async {
    String characterName = _nameCache[senderId] ?? await _getCharacterName(senderId);
    String role = await _getUserRole(senderId);
    
    await _firestore.collection('carpet_chat').add({
      'senderId': senderId,
      'senderName': characterName,
      'senderRole': role,
      if (text != null) 'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType,
    });
  }

  Future<String> _getCharacterName(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('character_name')
          .eq('id', userId)
          .single()
          .timeout(const Duration(seconds: 3));

      _nameCache[userId] = response['character_name'] ?? 'Неизвестный';
      return _nameCache[userId]!;
    } catch (e) {
      return 'Неизвестный';
    }
  }

  Future<String> _getUserRole(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single()
          .timeout(const Duration(seconds: 3));

      return response['role'] ?? 'user';
    } catch (e) {
      return 'user';
    }
  }

  Stream<QuerySnapshot> getMessagesStream() {
    return _firestore
        .collection('carpet_chat')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}