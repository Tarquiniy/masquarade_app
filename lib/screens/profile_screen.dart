import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/blocs/auth/auth_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_state.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/screens/coin_flip_screen.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';

class ProfileScreen extends StatelessWidget {
  final ProfileModel profile;

  const ProfileScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          _buildContent(context),
          _buildPillarsSection(context),
          _buildAuraRequestSection(context),
          _buildCoinFlipSection(context),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 150.0,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          profile.characterName,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(blurRadius: 10.0, color: Colors.black)],
          ),
        ),
        centerTitle: true,
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/vtm_background.jpg',
              fit: BoxFit.cover,
              color: Colors.black.withOpacity(0.7),
              colorBlendMode: BlendMode.darken,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.redAccent),
          onPressed: () => context.read<AuthBloc>().add(LogoutRequested()),
          tooltip: 'Выйти',
        ),
      ],
      backgroundColor: const Color(0xFF1a0000),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _buildCharacterInfo(context),
          const SizedBox(height: 24),
          _buildStatsSection(context),
          const SizedBox(height: 24),
          _buildDomainSection(context),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildCharacterInfo(BuildContext context) {
    return Card(
      color: const Color(0xFF2a0000).withOpacity(0.8),
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Color(0xFF8b0000), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ИНФОРМАЦИЯ О ПЕРСОНАЖЕ',
              style: TextStyle(
                color: Color(0xFFd4af37),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const Divider(color: Color(0xFF8b0000), height: 24),
            _buildInfoRow('Клан', profile.clan, Icons.bloodtype),
            _buildInfoRow('Секта', profile.sect, Icons.group),
            _buildInfoRow('Статус', profile.status, Icons.star),
            _buildInfoRow('Роль', profile.role, Icons.security),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFd4af37), size: 20),
          const SizedBox(width: 12),
          Text(
            '$title: ',
            style: const TextStyle(
              color: Color(0xFFd4af37),
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        final currentProfile = (state is ProfileLoaded)
            ? state.profile
            : profile;
        return Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ХАРАКТЕРИСТИКИ',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Divider(color: Color(0xFF8b0000), height: 24),
                // Сила крови
                _buildStatValue(
                  'Сила крови',
                  '${currentProfile.bloodPower}',
                  Icons.whatshot,
                ),
                // Голод
                _buildStatBar(
                  'Голод',
                  currentProfile.hunger,
                  5,
                  Icons.local_dining,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Новый виджет для отображения силы крови как цифры
  Widget _buildStatValue(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFd4af37), size: 20),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Color(0xFFd4af37),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBar(String label, int value, int max, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFd4af37), size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFd4af37),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '$value/$max',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value / max,
            backgroundColor: Colors.grey[800],
            color: value < max / 2
                ? const Color(0xFF8b0000)
                : const Color(0xFFd4af37),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainSection(BuildContext context) {
    return BlocBuilder<DomainBloc, DomainState>(
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

        return Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ВЛАДЕНИЯ',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Divider(color: Color(0xFF8b0000), height: 24),

                if (userDomain != null && userDomain.id != -1)
                  _buildDomainStats(userDomain)
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Text(
                        'Вы не владеете никакими территориями',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: profile.disciplines
                      .map(
                        (d) => Chip(
                          label: Text(
                            d,
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: const Color(0xFF8b0000),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: Color(0xFFd4af37)),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDomainStats(DomainModel domain) {
    return Column(
      children: [
        _buildDomainStat('Название', domain.name, Icons.location_city),
        _buildDomainStat(
          'Защищённость',
          '${domain.securityLevel}',
          Icons.security,
        ),
        _buildDomainStat(
          'Доход',
          '${domain.income}/день',
          Icons.monetization_on,
        ),
        _buildDomainStat(
          'Нарушения',
          '${domain.openViolationsCount}',
          Icons.warning,
        ),
      ],
    );
  }

  Widget _buildDomainStat(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFd4af37), size: 20),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Color(0xFFd4af37),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPillarsSection(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverToBoxAdapter(
        child: Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'СТОЛПЫ ЛИЧНОСТИ',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Divider(color: Color(0xFF8b0000), height: 24),
                ...profile.pillars
                    .map((pillar) => _buildPillarTile(context, pillar))
                    .toList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillarTile(BuildContext context, Map<String, dynamic> pillar) {
    final isDestroyed = pillar['destroyed'] ?? false;

    return ListTile(
      title: Text(
        pillar['name'] ?? 'Неизвестный столп',
        style: TextStyle(
          color: isDestroyed ? Colors.red : const Color(0xFFd4af37),
          decoration: isDestroyed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        pillar['description'] ?? 'Описание отсутствует',
        style: TextStyle(color: isDestroyed ? Colors.red[300] : Colors.white70),
      ),
      onLongPress: isDestroyed
          ? null
          : () {
              _showDestroyPillarDialog(context, pillar);
            },
    );
  }

  void _showDestroyPillarDialog(
    BuildContext context,
    Map<String, dynamic> pillar,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обрушить столп?'),
        content: Text(
          'Вы уверены, что хотите обрушить столп "${pillar['name']}"? '
          'Это действие необратимо и повлияет на вашу Человечность.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _destroyPillar(context, pillar);
            },
            child: const Text('Обрушить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _destroyPillar(BuildContext context, Map<String, dynamic> pillar) {
    final bloc = context.read<ProfileBloc>();
    final currentState = bloc.state;

    if (currentState is ProfileLoaded) {
      final currentProfile = currentState.profile;

      final updatedPillars = currentProfile.pillars.map((p) {
        if (p['name'] == pillar['name']) {
          return {...p, 'destroyed': true};
        }
        return p;
      }).toList();

      final updatedProfile = currentProfile.copyWith(pillars: updatedPillars);

      bloc.add(UpdateProfile(updatedProfile));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Столп "${pillar['name']}" обрушен!'),
          backgroundColor: Colors.red[900],
        ),
      );
    }
  }

  Widget _buildAuraRequestSection(BuildContext context) {
    final hasAuspex2 = profile.disciplines.contains('Прорицание 2');

    if (!hasAuspex2) {
      return SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverToBoxAdapter(
        child: Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ЗАПРОС АУРЫ',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Divider(color: Color(0xFF8b0000), height: 24),
                const Text(
                  'Выберите персонажа для чтения ауры:',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                _buildPlayerSelector(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSelector(BuildContext context) {
    return FutureBuilder<List<ProfileModel>>(
      future: context.read<ProfileBloc>().getPlayers(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final players = snapshot.data!;
        return DropdownButtonFormField<ProfileModel>(
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.grey[900],
          ),
          items: players.map((player) {
            return DropdownMenuItem(
              value: player,
              child: Text(
                player.characterName,
                style: TextStyle(color: Colors.white),
              ),
            );
          }).toList(),
          onChanged: (selected) {
            if (selected != null) {
              _sendAuraRequest(context, selected);
            }
          },
          hint: Text(
            'Выберите персонажа',
            style: TextStyle(color: Colors.grey),
          ),
        );
      },
    );
  }

  Widget _buildCoinFlipSection(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverToBoxAdapter(
        child: Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CoinFlipScreen()),
                    );
                  },
                  icon: Icon(Icons.monetization_on, color: Colors.amber),
                  label: Text(
                    'Подбросить монетку',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                    backgroundColor: Color(0xFF8b0000),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _sendAuraRequest(BuildContext context, ProfileModel target) {
    sendDebugToTelegram(
      '📡 Запрос ауры\n'
      'От: ${profile.characterName} (${profile.external_name})\n'
      'Персонаж: ${target.characterName}\n'
      'Username: ${target.external_name}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Запрос ауры на ${target.characterName} отправлен'),
        backgroundColor: Colors.purple,
      ),
    );
  }
}
