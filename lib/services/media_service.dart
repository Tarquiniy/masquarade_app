import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import '../env.dart'; // Импортируем сервисный ключ

class MediaService {
  late final SupabaseClient _client;

  MediaService(SupabaseClient? client) {
    // Создаем клиент с сервисной ролью для обхода RLS
    _client = client ?? SupabaseClient(
      supabase_url,
      supabase_serviceKey, // Используем сервисный ключ
      );
  }

  Future<String> uploadMedia(
    Uint8List bytes,
    String fileName,
    {required String fileType}
  ) async {
    final contentType = _getContentType(fileType);

    try {
      await _client.storage
        .from('carpet-chat.media')
        .uploadBinary(
          fileName,
          bytes,
          fileOptions: FileOptions(contentType: contentType),
        );

      return _client.storage
        .from('carpet-chat.media')
        .getPublicUrl(fileName);
    } catch (e) {
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