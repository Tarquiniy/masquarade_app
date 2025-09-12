import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FirebaseChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> sendMessage({
    required String senderId,
    String? text,
    String? mediaUrl,
    String? mediaType,
    int? duration,
    String? fileName,
  }) async {
    try {
      final profileData = await _supabase
          .from('profiles')
          .select()
          .eq('id', senderId)
          .maybeSingle();

      // ВСЕГДА сохраняем настоящее имя персонажа
      final characterName = profileData?['character_name'] as String? ?? 'Unknown';
      final role = profileData?['role'] as String? ?? 'user';

      await _firestore.collection('carpet_chat').add({
        'senderId': senderId,
        'senderName': characterName, // Сохраняем настоящее имя
        'realSenderName': characterName, // Дополнительное поле для администраторов
        'text': text,
        'mediaUrl': mediaUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'mediaType': mediaType,
        'duration': duration,
        'senderRole': role,
        'fileName': fileName,
      });
    } catch (e) {
      sendDebugToTelegram('Error sending message: $e');
      rethrow;
    }
  }

  Stream<QuerySnapshot> getMessagesStream() {
    return _firestore
        .collection('carpet_chat')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      await _firestore.collection('carpet_chat').doc(messageId).delete();
    } catch (e) {
      sendDebugToTelegram('Error deleting message: $e');
      rethrow;
    }
  }
}