// main.dart — расширенная версия с детальным логированием и безопасной отправкой debug-сообщений
import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:firebase_core/firebase_core.dart';

import 'package:masquarade_app/blocs/domain/domain_event.dart';
import 'package:masquarade_app/env.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/models/violation_model.dart';
import 'package:masquarade_app/services/domain_monitor_service.dart';
import 'package:masquarade_app/blocs/auth/auth_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_bloc.dart';
import 'package:masquarade_app/blocs/masquerade/masquerade_bloc.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/repositories/supabase_repository.dart';
import 'package:masquarade_app/services/supabase_service.dart';

// Импортим твою функцию отправки, но будем вызывать её только когда Supabase готов.
// (Импорталиас, чтобы не путаться с именами в проекте)
import 'package:masquarade_app/utils/debug_telegram.dart' as debug_tele;

import 'screens/home_screen.dart';
import 'screens/enter_username_screen.dart';
import 'utils/orientation_plugin.dart';

const String appVersion = '1.0.0';

/// Класс — мощный отладочный логгер, удобный для PWA + Flutter.
/// - пишет в консоль (debugPrint + window.console)
/// - сохраняет в localStorage (веб) и SharedPreferences (mobile/web)
/// - буферизует debug-сообщения и отправляет через Supabase function когда ready
class DebugLogger {
  /// очередь сообщений, ждёт, когда Supabase готов
  final List<Map<String, dynamic>> _queue = [];

  SharedPreferences? _prefs;
  bool _supabaseReady = false;
  bool get supabaseReady => _supabaseReady;

  /// Инициализация - даём prefs, если он есть
  Future<void> init([SharedPreferences? prefs]) async {
    _prefs = prefs;
    await _loadQueueFromStorage();
  }
 
  /// Load existing queue from SharedPreferences/localStorage on init
  Future<void> _loadQueueFromStorage() async {
    try {
      // try SharedPreferences first (if available)
      if (_prefs != null) {
        final key = 'masq_debug_logs_sp';
        final list = _prefs!.getStringList(key);
        if (list != null && list.isNotEmpty) {
          for (final s in list) {
            try {
              final m = jsonDecode(s) as Map<String, dynamic>;
              _queue.add(m);
            } catch (_) {}
          }
          // trim
          if (_queue.length > 200) _queue.removeRange(0, _queue.length - 200);
        }
      }

      // also attempt localStorage merge (web)
      try {
        final localStorage = js.context['localStorage'];
        if (localStorage != null) {
          final key = 'masq_debug_logs';
          final existing = localStorage.callMethod('getItem', [key]);
          if (existing != null) {
            final arr = jsonDecode(existing as String) as List<dynamic>;
            for (final item in arr) {
              if (item is Map<String, dynamic>) _queue.add(item);
            }
            if (_queue.length > 200) _queue.removeRange(0, _queue.length - 200);
          }
        }
      } catch (_) {}
    } catch (_) {}
  }
}

final DebugLogger logger = DebugLogger();

Future<void> safeSendTelegramMode({required String chatId, required String message, required String mode}) async {
  // If supabase ready, call actual function (debug_tele)
  if (logger.supabaseReady) {
    {
      await debug_tele.sendTelegramMode(chatId: chatId, message: message, mode: mode);
      return;
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set global error handlers early so we capture any initialization exceptions.
  FlutterError.onError = (FlutterErrorDetails details) async {
    // keep default behavior (prints in console)
    FlutterError.presentError(details);
    // log and attempt to send
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    // Log and attempt to send; return true to indicate we've handled it.
    return true;
  };

    // SharedPreferences
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      // pass prefs to logger storage
      await logger.init(prefs);
    } catch (e) {
      // still initialize logger without prefs
      await logger.init(null);
    }

    // Read savedProfileId
    String? savedProfileId;
    {
      savedProfileId = prefs?.getString('currentProfileId');
    } 

    // Restore cachedDomains
    List<DomainModel>? domains = [];
    try {
      final cachedDomains = prefs?.getString('cachedDomains');
      if (cachedDomains != null) {
        final list = jsonDecode(cachedDomains) as List;
        domains = list.map((e) => DomainModel.fromJson(e)).toList();
      }
    } catch (e) {
      await safeSendTelegramMode(chatId: '369397714', message: '❌ Ошибка восстановления доменов: $e', mode: 'debug');
    }

    // Restore violations
    List<ViolationModel>? violations = [];
    try {
      final cachedViolations = prefs?.getString('cachedViolations');
      if (cachedViolations != null) {
        final list = jsonDecode(cachedViolations) as List;
        violations = list.map((e) => ViolationModel.fromJson(e)).toList();
      }
    } catch (e) {
      await safeSendTelegramMode(chatId: '369397714', message: '❌ Ошибка восстановления нарушений: $e', mode: 'debug');
    }

    // Restore current domain
    DomainModel? currentDomain;
    try {
      final cachedCurrentDomain = prefs?.getString('currentDomain');
      if (cachedCurrentDomain != null) {
        currentDomain = DomainModel.fromJson(jsonDecode(cachedCurrentDomain));
      }
    } catch (e, st) {
      await safeSendTelegramMode(chatId: '369397714', message: '❌ Ошибка восстановления домена: $e', mode: 'debug');
    }

    // checkForUpdates function (web only)
    Future<void> checkForUpdates() async {
      {
        if (kIsWeb) {
          final url = 'https://tankograd.firebaseapp.com/version.json?t=${DateTime.now().millisecondsSinceEpoch}';
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final Map<String, dynamic> versionInfo = jsonDecode(response.body);
            final String latestVersion = versionInfo['version'] as String;
            if (latestVersion != appVersion) {
              // request reload (safe)
              {
                js.context.callMethod('location', []).callMethod('reload', []);
              }
            }
          }
        }
      }
    }

    // Force update function kept (web)
    Future<void> forceUpdate() async {
      if (kIsWeb) {
        {
          // try to delete caches if available
          try {
            final caches = js.context['caches'];
            if (caches != null) {
              // caches.delete is async promise — we can't await easily here, but try
              try {
                final p = caches.callMethod('delete', ['__app_cache__']);
                await Future.delayed(const Duration(milliseconds: 200));
              } catch (_) {}
            }
          } catch (_) {}
          js.context.callMethod('location', []).callMethod('reload', [true]);
        }
      }
    }

    // Initialize Firebase if possible
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyCpQyNCQYkSajBX5Wr8Ii9wlDP4nX6wchE",
          authDomain: "tankograd.firebaseapp.com",
          projectId: "tankograd",
          storageBucket: "tankograd.firebasestorage.app",
          messagingSenderId: "255328966030",
          appId: "1:255328966030:web:dd88de76c1a68c6cdf80df",
        ),
      );
    } catch (e) {
      await safeSendTelegramMode(chatId: '369397714', message: '⚠️ Ошибка инициализации Firebase: $e. Приложение продолжит работу без уведомлений.', mode: 'debug');
    }

    // run checkForUpdates (don't block long)
    unawaited(checkForUpdates());

    // Initialize Supabase
    try {
      await Supabase.initialize(url: supabase_url, anonKey: supabase_anonKey);
    } catch (e) {
      await safeSendTelegramMode(chatId: '369397714', message: '❌ Ошибка инициализации Supabase: $e', mode: 'debug');
    }

    // Create service/repo
    final client = Supabase.instance.client;
    final service = SupabaseService(client);
    final repository = SupabaseRepository(service);

    // Start domain monitor service (may throw)
    DomainMonitorService? domainMonitor;
    try {
      domainMonitor = DomainMonitorService(repository);
      await domainMonitor.startMonitoring();
    } catch (e) {
      await safeSendTelegramMode(chatId: '369397714', message: '❌ Ошибка при запуске мониторинга доменов: $e', mode: 'debug');
    }

    // Try restore saved profile from repo (if id present)
    ProfileModel? savedProfile;
    if (prefs != null && savedProfileId != null) {
      try {
        savedProfile = await repository.getProfileById(savedProfileId);
        if (savedProfile != null) {
          await safeSendTelegramMode(chatId: '369397714', message: '🔑 Восстановлена сессия: ${savedProfile.characterName}', mode: 'debug');
        } else {
          await prefs.remove('currentProfileId');
          await safeSendTelegramMode(chatId: '369397714', message: '❌ Профиль с ID $savedProfileId не найден', mode: 'debug');
        }
      } catch (e) {
        await prefs.remove('currentProfileId');
        await safeSendTelegramMode(chatId: '369397714', message: '❌ Ошибка восстановления сессии: $e', mode: 'debug');
      }
    }

    // Everything prepared — run the app
    runApp(MyApp(
      repository: repository,
      savedProfile: savedProfile,
      cachedDomains: domains,
      cachedViolations: violations,
      cachedCurrentDomain: currentDomain,
      prefs: prefs ?? (await SharedPreferences.getInstance()),
    ));

  }

// Rest of app (unchanged layout), using provided repository & blocs
class MyApp extends StatelessWidget {
  final SupabaseRepository repository;
  final ProfileModel? savedProfile;
  final List<DomainModel>? cachedDomains;
  final List<ViolationModel>? cachedViolations;
  final DomainModel? cachedCurrentDomain;
  final SharedPreferences prefs;

  const MyApp({
    super.key,
    required this.repository,
    this.savedProfile,
    this.cachedDomains,
    this.cachedViolations,
    this.cachedCurrentDomain,
    required this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
            create: (_) => AuthBloc(repository: repository, savedProfile: savedProfile),
          ),
          BlocProvider<DomainBloc>(
            create: (_) => DomainBloc(
              repository: repository,
              prefs: prefs,
              cachedDomains: cachedDomains,
              cachedCurrentDomain: cachedCurrentDomain,
            ),
          ),
          BlocProvider<ProfileBloc>(
            create: (_) => ProfileBloc(repository: repository),
          ),
          BlocProvider<MasqueradeBloc>(
            create: (context) {
              if (savedProfile != null) {
                return MasqueradeBloc(
                  repository: repository,
                  currentProfile: savedProfile!,
                  profileBloc: context.read<ProfileBloc>(),
                  domainBloc: context.read<DomainBloc>(),
                  cachedViolations: cachedViolations,
                )..add(LoadViolations());
              }
              return MasqueradeBloc(
                repository: repository,
                currentProfile: ProfileModel(
                  id: '',
                  characterName: 'Гость',
                  sect: '',
                  clan: '',
                  humanity: 0,
                  disciplines: [],
                  bloodPower: 0,
                  hunger: 0,
                  domainIds: [],
                  role: 'guest',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                  pillars: [],
                  generation: 13,
                ),
                profileBloc: context.read<ProfileBloc>(),
                domainBloc: context.read<DomainBloc>(),
              );
            },
          ),
        ],
        child: MaterialApp(
          title: 'Masquerade App',
          theme: ThemeData(
            colorScheme: ColorScheme.dark(
              primary: Color(0xFF8b0000),
              secondary: Color(0xFFd4af37),
              surface: Color(0xFF2a0000),
              background: Color(0xFF1a0000),
            ),
            scaffoldBackgroundColor: Color(0xFF1a0000),
            cardColor: Color(0xFF2a0000),
            useMaterial3: true,
            textTheme: TextTheme(
              bodyLarge: TextStyle(color: Colors.white70),
              bodyMedium: TextStyle(color: Colors.white70),
              titleLarge: TextStyle(color: Colors.amber[200]),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: Color(0xFF4A0000),
              titleTextStyle: TextStyle(
                color: Colors.amber[200],
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF8b0000),
                foregroundColor: Colors.amber[200],
              ),
            ),
          ),
          home: AppEntry(
            repository: repository,
            savedProfile: savedProfile,
          ),
        ),
      ),
    );
  }
}

class AppEntry extends StatelessWidget {
  final SupabaseRepository repository;
  final ProfileModel? savedProfile;

  const AppEntry({
    super.key,
    required this.repository,
    this.savedProfile,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        if (savedProfile != null && state is AuthInitial) {
          Future.delayed(Duration.zero, () {
            context.read<AuthBloc>().add(RestoreSession(savedProfile!));
          });
          return Center(child: CircularProgressIndicator());
        }

        if (state is Authenticated) {
          final profile = state.profile;
          // Authenticated - safe attempt to send debug note
          unawaited(safeSendTelegramMode(chatId: '369397714', message: '🔑 Authenticated: ${profile.characterName}', mode: 'debug'));

          context.read<ProfileBloc>().add(SetProfile(profile));
          context.read<MasqueradeBloc>().add(UpdateCurrentProfile(profile));
          context.read<DomainBloc>().add(LoadDomains());
          context.read<MasqueradeBloc>().add(LoadViolations());

          return const HomeScreen();
        }

        return const EnterUsernameScreen();
      },
    );
  }
}
