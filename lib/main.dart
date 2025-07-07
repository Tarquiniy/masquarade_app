import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'screens/home_screen.dart';
import 'screens/enter_username_screen.dart';
import 'screens/profile_screen.dart';

import 'blocs/auth/auth_bloc.dart';
import 'blocs/domain/domain_bloc.dart';
import 'blocs/masquerade/masquerade_bloc.dart';
import 'blocs/profile/profile_bloc.dart';

import 'repositories/supabase_repository.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pedqpjmdhkcdssfshpzb.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBlZHFwam1kaGtjZHNzZnNocHpiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgwNzg2MjEsImV4cCI6MjA2MzY1NDYyMX0.TpKphT5OsfflOP6-ECNmcWckYsvSwRXzRkRhIevUG-I',
  );

  final service = SupabaseService(Supabase.instance.client);
  // Убрали вызов checkViolationsTable, так как он должен быть в SupabaseService

  final repository = SupabaseRepository(service);
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
        BlocProvider<ProfileBloc>(create: (_) => ProfileBloc()),
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
        if (state is Authenticated) {
          final profile = state.profile;

          // Устанавливаем профиль в ProfileBloc
          context.read<ProfileBloc>().add(SetProfile(profile));

          return BlocProvider(
            create: (_) =>
                MasqueradeBloc(repository: repository, currentProfile: profile)
                  ..add(LoadViolations()),
            child: HomeScreen(profile: profile),
          );
        }

        return const EnterUsernameScreen();
      },
    );
  }
}
