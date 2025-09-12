import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:masquarade_app/blocs/domain/domain_event.dart';
import 'package:masquarade_app/env.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/models/violation_model.dart';
import 'package:masquarade_app/services/domain_monitor_service.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:js' as js;
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/home_screen.dart';
import 'screens/enter_username_screen.dart';
import 'blocs/auth/auth_bloc.dart';
import 'blocs/domain/domain_bloc.dart';
import 'blocs/masquerade/masquerade_bloc.dart';
import 'blocs/profile/profile_bloc.dart';
import 'repositories/supabase_repository.dart';
import 'services/supabase_service.dart';
import 'utils/orientation_plugin.dart';

const String appVersion = '1.0.0';

Future <void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация плагина ориентации
  OrientationPlugin.initialize();

  // Загружаем SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final savedProfileId = prefs.getString('currentProfileId');

  // Восстанавливаем домены
  final cachedDomains = prefs.getString('cachedDomains');
  List<DomainModel>? domains = [];
  if (cachedDomains != null) {
    try {
      final list = jsonDecode(cachedDomains) as List;
      domains = list.map((e) => DomainModel.fromJson(e)).toList();
      sendDebugToTelegram('📀 Восстановлено ${domains.length} доменов из кеша');
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка восстановления доменов: $e');
    }
  }

  // Восстанавливаем нарушения
  final cachedViolations = prefs.getString('cachedViolations');
  List<ViolationModel>? violations = [];
  if (cachedViolations != null) {
    try {
      final list = jsonDecode(cachedViolations) as List;
      violations = list.map((e) => ViolationModel.fromJson(e)).toList();
      sendDebugToTelegram('📀 Восстановлено ${violations.length} нарушений из кеша');
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка восстановления нарушений: $e');
    }
  }

  // Восстанавливаем текущий домен
  final cachedCurrentDomain = prefs.getString('currentDomain');
  DomainModel? currentDomain;
  if (cachedCurrentDomain != null) {
    try {
      currentDomain = DomainModel.fromJson(jsonDecode(cachedCurrentDomain));
      sendDebugToTelegram('📀 Восстановлен текущий домен: ${currentDomain.name}');
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка восстановления домена: $e');
    }
  }

  Future<void> checkForUpdates() async {
  try {
    if (kIsWeb) {
      final response = await http.get(
        Uri.parse('https://tankograd.firebaseapp.com/version.json?t=${DateTime.now().millisecondsSinceEpoch}'),
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> versionInfo = jsonDecode(response.body);
        final String latestVersion = versionInfo['version'];
        
        if (latestVersion != appVersion) {
          // Если версии отличаются, принудительно обновляем страницу
          js.context.callMethod('reload', []);
        }
      }
    }
  } catch (e) {
    print('Ошибка при проверке обновлений: $e');
  }
}

Future<void> forceUpdate() async {
  if (kIsWeb) {
    // Очистка кэша и перезагрузка
    try {
      if (js.context.hasProperty('caches')) {
        js.context.callMethod('caches', []).callMethod('delete', []);
      }
    } catch (e) {
      print('Ошибка при очистке кэша: $e');
    }
    
    // Принудительная перезагрузка
    js.context.callMethod('location', []).callMethod('reload', [true]);
  }
}

  // Инициализация Firebase - ОБЕРНУТА В TRY-CATCH ДЛЯ БЕЗОПАСНОСТИ
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyCpQyNCQYkSajBX5Wr8Ii9wlDP4nX6wchE",
        authDomain: "tankograd.firebaseapp.com",
        projectId: "tankograd",
        storageBucket: "tankograd.firebasestorage.app",
        messagingSenderId: "255328966030",
        appId: "1:255328966030:web:dd88de76c1a68c6cdf80df"
      ),
    );

  } catch (e) {
    sendDebugToTelegram('⚠️ Ошибка инициализации Firebase: $e. Приложение продолжит работу без уведомлений.');
  }

    await checkForUpdates();

  await Supabase.initialize(url: supabase_url, anonKey: supabase_anonKey);

  final client = Supabase.instance.client;
  final service = SupabaseService(client);
  final repository = SupabaseRepository(service);

  final domainMonitor = DomainMonitorService(repository);
  await domainMonitor.startMonitoring();


  ProfileModel? savedProfile;
  if (savedProfileId != null) {
    try {
      savedProfile = await repository.getProfileById(savedProfileId);
      if (savedProfile != null) {
        sendDebugToTelegram('🔑 Восстановлена сессия: ${savedProfile.characterName}');

      } else {
        sendDebugToTelegram('❌ Профиль с ID $savedProfileId не найден');
        await prefs.remove('currentProfileId');
      }
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка восстановления сессии: $e');
      await prefs.remove('currentProfileId');
    }
  }

  runApp(MyApp(
    repository: repository,
    savedProfile: savedProfile,
    cachedDomains: domains,
    cachedViolations: violations,
    cachedCurrentDomain: currentDomain,
    prefs: prefs,
  ));
}

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
            create: (_) => AuthBloc(
              repository: repository,
              savedProfile: savedProfile
            ),
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
                  pillars: [], generation: 13,
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
        sendDebugToTelegram('🔄 AuthState: $state');

        if (savedProfile != null && state is AuthInitial) {
          Future.delayed(Duration.zero, () {
            context.read<AuthBloc>().add(RestoreSession(savedProfile!));
          });
          return Center(child: CircularProgressIndicator());
        }

        if (state is Authenticated) {
          final profile = state.profile;
          sendDebugToTelegram('🔑 Authenticated: ${profile.characterName}');

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