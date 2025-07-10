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
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
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
            create: (_) =>
                MasqueradeBloc(repository: repository, currentProfile: profile)
                  ..add(LoadViolations()),
            child: const HomeScreen(),
          );
        }

        return const EnterUsernameScreen();
      },
    );
  }
}
