import 'dart:typed_data';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../env.dart';

class MediaService {
  final SupabaseClient _clientForStorage;
  final String _bucketName = 'carpet-chat.media';

  MediaService() 
    : _clientForStorage = SupabaseClient(supabase_url, supabase_serviceKey);

  Future<String> uploadMedia(
    Uint8List bytes,
    String fileName, {
    required String fileType,
  }) async {
    try {
      await _clientForStorage.storage
        .from(_bucketName)
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(
            contentType: _getContentType(fileType),
            upsert: true,
          ),
        );

      return _clientForStorage.storage
        .from(_bucketName)
        .getPublicUrl(fileName);
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка загрузки: $e');
      throw Exception('Ошибка загрузки: $e');
    }
  }

  String _getContentType(String fileType) {
    return fileType == 'image'
        ? 'image/jpeg'
        : fileType == 'audio'
            ? 'audio/mpeg'
            : 'application/octet-stream';
  }
}