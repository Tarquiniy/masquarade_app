import 'package:http/http.dart' as http;

const String telegramBotToken =
    '7594245609:AAGK4IWj3G9zJf1HY1B2p6XGBEHF1AbLOa4';
const String chatId = '369397714'; // Добавьте эту строку

Future<void> sendDebugToTelegram(String message) async {
  try {
    final url = Uri.parse(
      'https://api.telegram.org/bot$telegramBotToken/sendMessage',
    );

    // Форматируем сообщение с сохранением переносов строк
    final formattedMessage = message
        .replaceAll('\n', ' f')
        .replaceAll('%20', ' ');

    final response = await http.post(
      url,
      body: {
        'chat_id': chatId, // Теперь переменная определена
        'text': formattedMessage,
      },
    );

    if (response.statusCode != 200) {
      print('Telegram error: ${response.body}');
    }
  } catch (e) {
    print('Telegram send failed: $e');
  }
}
