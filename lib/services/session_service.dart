import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

class SessionService {
  static const _key = 'session_id';
  String? _sessionId;

  Future<void> init() async {
    if (kIsWeb) {
      _sessionId = html.window.localStorage[_key];
    } else {
      final prefs = await SharedPreferences.getInstance();
      _sessionId = prefs.getString(_key);
    }
  }

  Future<void> setSessionId(String id) async {
    _sessionId = id;
    if (kIsWeb) {
      html.window.localStorage[_key] = id;
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, id);
    }
  }

  String? getSessionId() => _sessionId;

  Future<void> clearSession() async {
    _sessionId = null;
    if (kIsWeb) {
      html.window.localStorage.remove(_key);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    }
  }
}
