import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Flutter: Вспомогательные функции для отправки уведомлений через Supabase Function и дебага.

/// Эта функция вызывает Supabase Edge Function "sendTelegram" с параметрами.
/// mode: "notification" или "debug"
Future<void> sendTelegramMode({
  required String chatId,          // для notification: telegramChatId пользователя
  required String message,
  required String mode,            // "notification" или "debug"
}) async {
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'sendTelegram',
      body: {
        'text': message,
        'chat_id': chatId,
        'mode': mode,
      },
    );

    // Проверка ответа
    dynamic resp = response;

    bool hasError = false;
    String? errorMsg;

    // Если resp.data содержит { error: ... }
    if (resp.data is Map<String, dynamic> &&
        (resp.data as Map<String, dynamic>)['error'] != null) {
      hasError = true;
      errorMsg = (resp.data as Map<String, dynamic>)['error'].toString();
    }

    if (hasError) {
      // Отправляем дебаг
      await sendTelegramMode(
        chatId: '369397714',                    // chatId не важен, debug mode использует секретный chat
        message: '❌ Функция sendTelegram вернула ошибку: $errorMsg',
        mode: 'debug',
      );
    } else {
      print('sendTelegramMode success: ${resp.data}');
    }
  } catch (e) {
    await sendTelegramMode(
      chatId: '369397714',
      message: '❌ sendTelegramMode вызов не удался: $e',
      mode: 'debug',
    );
  }
}
