import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/blocs/auth/auth_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_state.dart';
import '../blocs/domain/domain_bloc.dart';
import '../models/domain_model.dart';
import '../models/profile_model.dart';

class ProfileScreen extends StatelessWidget {
  final ProfileModel profile;

  const ProfileScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [_buildAppBar(context), _buildContent(context)],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 220.0,
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
              'assets/vtm_background.jpg', // Добавьте файл в assets
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
          _buildCharacterInfo(),
          const SizedBox(height: 24),
          _buildStatsSection(),
          const SizedBox(height: 24),
          _buildDomainSection(context),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildCharacterInfo() {
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

  Widget _buildStatsSection() {
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
            _buildStatBar('Сила крови', profile.bloodPower, 10, Icons.whatshot),
            _buildStatBar('Голод', profile.hunger, 5, Icons.local_dining),
            _buildStatBar('Влияние', profile.totalInfluence, 10, Icons.public),
          ],
        ),
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
}
