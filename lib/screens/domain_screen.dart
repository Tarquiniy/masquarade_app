import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:masquarade_app/blocs/domain/domain_event.dart';
import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/profile/profile_bloc.dart';
import '../models/domain_model.dart';
import '../models/profile_model.dart';
import '../blocs/masquerade/masquerade_bloc.dart';
import '../models/violation_model.dart';

class DomainScreen extends StatelessWidget {
  const DomainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ProfileBloc>().state;
    final domainState = context.watch<DomainBloc>().state;

    // ВАЖНО: добавляем эту строчку
    context.read<MasqueradeBloc>().add(LoadViolations());

    if (profileState is! ProfileLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = profileState.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Мой домен')),
      body: domainState is DomainsLoaded
          ? _buildDomainContent(context, profile, domainState.domains)
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildDomainContent(
    BuildContext context,
    ProfileModel profile,
    List<DomainModel> domains,
  ) {
    final userDomain = domains.firstWhere(
      (d) => d.ownerId == profile.id,
      orElse: () => DomainModel(
        id: -1,
        name: 'Нет домена',
        ownerId: '',
        latitude: 0,
        longitude: 0,
        boundaryPoints: [],
      ),
    );

    if (userDomain.id == -1) {
      return const Center(child: Text('У вас нет домена.'));
    }

    final center = userDomain.boundaryPoints.isNotEmpty
        ? userDomain.boundaryPoints.first
        : const LatLng(55.751244, 37.618423);

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              ),
              if (userDomain.boundaryPoints.isNotEmpty)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: userDomain.boundaryPoints,
                      color: Colors.blue.withOpacity(0.3),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Ваш домен: ${userDomain.name}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => _transferDomain(context, userDomain.id),
              child: const Text('Передать домен'),
            ),
          ],
        ),
        const Divider(),
        Text('Защищенность: ${userDomain.securityLevel}'),
        Text('Влиятельность: ${userDomain.influenceLevel}'),
        Row(
          children: [
            Expanded(child: Text('Доходность: ${userDomain.income}')),
            ElevatedButton(
              onPressed: () =>
                  _showHungerTransferDialog(context, userDomain.income),
              child: const Text('Передать'),
            ),
          ],
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            'Нарушения маскарада',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        BlocBuilder<MasqueradeBloc, MasqueradeState>(
          builder: (context, state) {
            if (state is ViolationsLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is ViolationsLoaded) {
              final violationsInDomain = state.violations
                  .where((v) => v.domainId == userDomain.id)
                  .toList();

              if (violationsInDomain.isEmpty) {
                return const Text('Нарушений на территории домена нет');
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: violationsInDomain.length,
                itemBuilder: (_, idx) {
                  final v = violationsInDomain[idx];
                  return ListTile(
                    title: Text(v.description),
                    subtitle: Text(v.status.name),
                  );
                },
              );
            } else {
              return const SizedBox.shrink();
            }
          },
        ),
      ],
    );
  }

  void _transferDomain(BuildContext context, int domainId) async {
    final players = await context.read<ProfileBloc>().getPlayers();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Выберите игрока'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: players.length,
            itemBuilder: (_, i) {
              final p = players[i];
              return ListTile(
                title: Text(p.characterName),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDomainTransfer(context, domainId, p);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _confirmDomainTransfer(
    BuildContext context,
    int domainId,
    ProfileModel recipient,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтверждение передачи'),
        content: Text(
          'Вы ТОЧНО хотите передать свой домен ${recipient.characterName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<DomainBloc>().repository.transferDomain(
                domainId.toString(),
                recipient.id,
              );
              context.read<DomainBloc>().add(
                RefreshDomains(
                  (context.read<ProfileBloc>().state as ProfileLoaded).profile,
                ),
              );
            },
            child: const Text('Да'),
          ),
        ],
      ),
    );
  }

  void _showHungerTransferDialog(BuildContext context, int maxHunger) {
    int hungerToTransfer = 1;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Передача пунктов голода'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: hungerToTransfer > 1
                          ? () => setState(() => hungerToTransfer--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Text('$hungerToTransfer'),
                    IconButton(
                      onPressed: hungerToTransfer < maxHunger
                          ? () => setState(() => hungerToTransfer++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () =>
                      _chooseHungerRecipient(context, hungerToTransfer),
                  child: const Text('Выбрать получателя'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _chooseHungerRecipient(
    BuildContext context,
    int hungerToTransfer,
  ) async {
    final players = await context.read<ProfileBloc>().getPlayers();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Выберите игрока'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: players.length,
            itemBuilder: (_, i) {
              final p = players[i];
              return ListTile(
                title: Text(p.characterName),
                onTap: () {
                  Navigator.pop(context);
                  _confirmHungerTransfer(context, p, hungerToTransfer);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _confirmHungerTransfer(
    BuildContext context,
    ProfileModel recipient,
    int amount,
  ) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтверждение передачи'),
        content: Text(
          'Вы хотите передать $amount пунктов голода ${recipient.characterName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<DomainBloc>().repository.transferHunger(
                fromUserId: (context.read<ProfileBloc>().state as ProfileLoaded)
                    .profile
                    .id,
                toUserId: recipient.id,
                amount: amount,
              );
            },
            child: const Text('Да'),
          ),
        ],
      ),
    );
  }
}
