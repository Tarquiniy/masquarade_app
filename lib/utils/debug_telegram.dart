import 'package:http/http.dart' as http;

const String debugBotToken = '7594245609:AAGK4IWj3G9zJf1HY1B2p6XGBEHF1AbLOa4';
const String debugChatId = '369397714';
const String notificationBotToken = '8398725116:AAHlIONC2IMvX54M6jtFpAiwIRTpgzZ6DVk';

// Для дебаг-сообщений (как было)
Future<void> sendDebugToTelegram(String message) async {
  try {
    final url = Uri.parse(
      'https://api.telegram.org/bot$debugBotToken/sendMessage',
    );

    final formattedMessage = message
        .replaceAll('\n', ' ')
        .replaceAll('%20', ' ');

    final response = await http.post(
      url,
      body: {'chat_id': debugChatId, 'text': formattedMessage},
    );

    if (response.statusCode != 200) {
      print('Debug bot error: ${response.body}');
    }
  } catch (e) {
    print('Debug bot send failed: $e');
  }
}

// Функция для отправки сообщения по chat_id через бот уведомлений
Future<void> sendTelegramMessageDirect(String chatId, String message) async {
  try {
    final url = Uri.parse(
      'https://api.telegram.org/bot$notificationBotToken/sendMessage',
    );

    final response = await http.post(
      url,
      body: {
        'chat_id': chatId,
        'text': message,
        'parse_mode': 'HTML'
      },
    );

    if (response.statusCode != 200) {
      ('Notification error for $chatId: ${response.body}');
      // Логируем ошибку в дебаг-бот
      sendDebugToTelegram('❌ Ошибка отправки уведомления для $chatId: ${response.body}');
    }
  } catch (e) {
    print('Notification send to $chatId failed: $e');
    sendDebugToTelegram('❌ Ошибка отправки уведомления для $chatId: $e');
  }
}