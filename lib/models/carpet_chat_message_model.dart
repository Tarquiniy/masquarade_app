import 'package:cloud_firestore/cloud_firestore.dart';

class CarpetChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String? text;
  final String? mediaUrl;
  final Timestamp timestamp;
  final String? mediaType;
  final String senderRole;
  final int? duration;
  final String? fileName;

  CarpetChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.text,
    this.mediaUrl,
    required this.timestamp,
    this.mediaType,
    required this.senderRole,
    this.duration,
    this.fileName,
  });

  factory CarpetChatMessage.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return CarpetChatMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Неизвестный',
      text: data['text'],
      mediaUrl: data['mediaUrl'],
      timestamp: data['timestamp'] ?? Timestamp.now(),
      mediaType: data['mediaType'],
      senderRole: data['senderRole'] ?? 'user',
      duration: data['duration'] != null ? data['duration'] as int? : null,
      fileName: data['fileName'],
    );
  }
}