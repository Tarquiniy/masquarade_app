import 'package:http/http.dart' as http;

Future<void> sendDebugToTelegram(String text) async {
  const token =
      '7594245609:AAGK4IWj3G9zJf1HY1B2p6XGBEHF1AbLOa4'; // 🔐 Вставь свой токен сюда
  const chatId = '369397714'; // Твой Telegram user ID

  final url = Uri.parse('https://api.telegram.org/bot$token/sendMessage');

  try {
    final response = await http.post(
      url,
      body: {'chat_id': chatId, 'text': text, 'parse_mode': 'HTML'},
    );

    if (response.statusCode != 200) {
      print('Telegram error: ${response.body}');
    }
  } catch (e) {
    print('Telegram send failed: $e');
  }
}
