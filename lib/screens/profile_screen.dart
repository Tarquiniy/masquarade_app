import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/blocs/auth/auth_bloc.dart';
import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_state.dart';
import '../models/domain_model.dart';
import '../models/profile_model.dart';

class ProfileScreen extends StatelessWidget {
  final ProfileModel profile;

  const ProfileScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: BlocBuilder<DomainBloc, DomainState>(
        builder: (context, domainState) {
          DomainModel? userDomain;

          if (domainState is DomainsLoaded) {
            userDomain = domainState.domains.firstWhere(
              (d) => d.ownerId == profile.id,
              orElse: () => DomainModel(
                id: -1,
                name: 'Нет домена',
                latitude: 0,
                longitude: 0,
                boundaryPoints: [],
                ownerId: '',
              ),
            );
          }

          return _buildProfileContent(context, profile, userDomain);
        },
      ),
    );
  }

  Widget _buildProfileContent(
    BuildContext context,
    ProfileModel profile,
    DomainModel? userDomain,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _title('Имя персонажа'),
        Text(profile.characterName, style: _valueStyle()),

        const SizedBox(height: 12),
        _title('Клан'),
        Text(profile.clan, style: _valueStyle()),

        const SizedBox(height: 12),
        _title('Секта'),
        Text(profile.sect, style: _valueStyle()),

        const SizedBox(height: 12),
        _title('Статус'),
        Text(profile.status, style: _valueStyle()),

        const SizedBox(height: 12),
        _title('Дисциплины'),
        Wrap(
          spacing: 8,
          children: profile.disciplines
              .map((d) => Chip(label: Text(d)))
              .toList(),
        ),

        const Divider(height: 32),

        _title('Сила крови'),
        Text('${profile.bloodPower}', style: _valueStyle()),

        const SizedBox(height: 12),
        _title('Голод'),
        Text('${profile.hunger}/6', style: _valueStyle()),

        const SizedBox(height: 12),
        _title('Влияние'),
        Text('${profile.influence}/7', style: _valueStyle()),

        const SizedBox(height: 12),
        _title('Домен'),
        Text(
          userDomain != null && userDomain.id != -1
              ? userDomain.name
              : profile.domainId != null
              ? 'Домен #${profile.domainId}'
              : 'нет',
          style: _valueStyle(),
        ),

        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () {
            context.read<AuthBloc>().add(LogoutRequested());
          },
          icon: const Icon(Icons.logout),
          label: const Text('Выйти из аккаунта'),
        ),

        const SizedBox(height: 24),
        const Text(
          'Данные обновляются администрацией. Напишите им для изменений.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _title(String title) => Text(
    title,
    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
  );

  TextStyle _valueStyle() => const TextStyle(fontSize: 16);
}
