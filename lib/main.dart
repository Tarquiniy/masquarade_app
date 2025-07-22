import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/env.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'screens/home_screen.dart';
import 'screens/enter_username_screen.dart';

import 'blocs/auth/auth_bloc.dart';
import 'blocs/domain/domain_bloc.dart';
import 'blocs/masquerade/masquerade_bloc.dart';
import 'blocs/profile/profile_bloc.dart';

import 'repositories/supabase_repository.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: supabase_url, anonKey: supabase_anonKey);

  final client = Supabase.instance.client;
  final service = SupabaseService(client);
  final repository = SupabaseRepository(service);

  final user = client.auth.currentUser;
  print('🚀 App started. Current user: ${user?.id ?? "none"}');

  runApp(MyApp(repository: repository));
}

class MyApp extends StatelessWidget {
  final SupabaseRepository repository;

  const MyApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(create: (_) => AuthBloc(repository: repository)),
        BlocProvider<DomainBloc>(
          create: (_) => DomainBloc(repository: repository),
        ),
        BlocProvider<ProfileBloc>(
          create: (_) => ProfileBloc(repository: repository),
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
        home: AppEntry(repository: repository),
      ),
    );
  }
}

class AppEntry extends StatelessWidget {
  final SupabaseRepository repository;

  const AppEntry({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        print('🔄 AuthState: $state');

        if (state is Authenticated) {
          final profile = state.profile;
          print('🔑 Authenticated: ${profile.characterName}');

          context.read<ProfileBloc>().add(SetProfile(profile));

          return BlocProvider(
            create: (_) => MasqueradeBloc(
              repository: repository,
              currentProfile: profile,
              profileBloc: context.read<ProfileBloc>(), // ДОБАВЛЕНО
            )..add(LoadViolations()),
            child: const HomeScreen(),
          );
        }

        return const EnterUsernameScreen();
      },
    );
  }
}
