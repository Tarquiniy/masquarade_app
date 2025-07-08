import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_event.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/profile/profile_bloc.dart';
import '../models/domain_model.dart';
import '../models/profile_model.dart';
import '../repositories/supabase_repository.dart';

class DomainScreen extends StatefulWidget {
  const DomainScreen({super.key});

  @override
  State<DomainScreen> createState() => _DomainScreenState();
}

class _DomainScreenState extends State<DomainScreen> {
  late final SupabaseRepository _repository;
  int? _selectedPlayerId;
  int _transferAmount = 1;
  Position? _position;

  @override
  void initState() {
    super.initState();
    _repository = RepositoryProvider.of<SupabaseRepository>(context);
    context.read<DomainBloc>().add(RefreshDomains());
  }

  // Передача домена
  Future<void> _transferDomain(BuildContext context, int domainId) async {
    final profiles = await _repository.getAllProfiles();
    final currentProfile =
        (context.read<ProfileBloc>().state as ProfileLoaded).profile;

    // Фильтруем профили, исключая текущего пользователя
    final candidates = profiles
        .where((p) => p.id != currentProfile.id)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Передать домен'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final profile = candidates[index];
              return ListTile(
                title: Text(profile.characterName),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDomainTransfer(context, domainId, profile);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  void _confirmDomainTransfer(
    BuildContext context,
    int domainId,
    ProfileModel newOwner,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение передачи'),
        content: Text(
          'Вы ТОЧНО хотите передать свой домен ${newOwner.characterName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _repository.transferDomain(
                domainId.toString(),
                newOwner.id,
              );
              if (mounted) {
                context.read<DomainBloc>().add(RefreshDomains());
                // Обновляем профиль текущего пользователя
                final profileState =
                    context.read<ProfileBloc>().state as ProfileLoaded;
                context.read<ProfileBloc>().add(
                  SetProfile(profileState.profile.copyWith(domainId: null)),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Передать'),
          ),
        ],
      ),
    );
  }

  // Передача пунктов голода
  void _showTransferHungerDialog(BuildContext context, int maxAmount) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Передача пунктов голода'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Выберите количество:'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _transferAmount > 1
                          ? () => setState(() => _transferAmount--)
                          : null,
                    ),
                    Text('$_transferAmount'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _transferAmount < maxAmount
                          ? () => setState(() => _transferAmount++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Выберите получателя:'),
                FutureBuilder<List<ProfileModel>>(
                  future: _repository.getAllProfiles(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const CircularProgressIndicator();
                    }

                    final profiles = snapshot.data!;
                    final currentProfile =
                        (context.read<ProfileBloc>().state as ProfileLoaded)
                            .profile;
                    final candidates = profiles
                        .where((p) => p.id != currentProfile.id)
                        .toList();

                    return DropdownButton<int>(
                      value: _selectedPlayerId,
                      hint: const Text('Выберите игрока'),
                      items: candidates.map((profile) {
                        return DropdownMenuItem<int>(
                          value: int.tryParse(profile.id),
                          child: Text(profile.characterName),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedPlayerId = value),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: _selectedPlayerId == null
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _confirmHungerTransfer(
                          context,
                          _transferAmount,
                          _selectedPlayerId!,
                        );
                      },
                child: const Text('Продолжить'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmHungerTransfer(
    BuildContext context,
    int amount,
    int recipientId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение передачи'),
        content: FutureBuilder<ProfileModel?>(
          future: _repository.getProfileById(recipientId.toString()),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            return Text(
              'Вы хотите передать $amount пунктов голода игроку ${snapshot.data!.characterName}?',
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final currentProfile =
                  (context.read<ProfileBloc>().state as ProfileLoaded).profile;
              await _repository.transferHunger(
                fromUserId: currentProfile.id,
                toUserId: recipientId.toString(),
                amount: amount,
              );
              // Обновляем профиль
              context.read<ProfileBloc>().add(
                SetProfile(
                  currentProfile.copyWith(
                    hunger: currentProfile.hunger - amount,
                  ),
                ),
              );
            },
            child: const Text('Передать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final domainState = context.watch<DomainBloc>().state;
    final profileState = context.watch<ProfileBloc>().state;

    if (profileState is! ProfileLoaded || domainState is! DomainsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = profileState.profile;
    final domain = domainState.domains.firstWhere(
      (d) => d.ownerId == profile.id,
      orElse: () => DomainModel(
        id: -1,
        name: 'Домен не найден',
        latitude: 0,
        longitude: 0,
        boundaryPoints: [],
        ownerId: '',
      ),
    );

    if (domain.id == -1) {
      return const Scaffold(
        body: Center(
          child: Text('У вас нет домена или произошла ошибка загрузки'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(domain.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => _transferDomain(context, domain.id),
            tooltip: 'Передать домен',
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 300,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _position != null
                    ? LatLng(_position!.latitude, _position!.longitude)
                    : const LatLng(55.751244, 37.618423),
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                ),
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: domain.boundaryPoints,
                      color: Colors.blue.withOpacity(0.3),
                      borderColor: Colors.blue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Статистика домена',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Защищенность: '),
                    Text('${domain.securityLevel}'),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Защищенность'),
                          content: const Text(
                            'Если за одну ночь в домене совершено нарушений '
                            'Маскарада больше или равно уровню Защищенности, '
                            'домен становится Нейтральным',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Влиятельность: '),
                    Text('${domain.influenceLevel}'),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Влиятельность'),
                          content: const Text(
                            'Складывается из статусов и влияния домена. '
                            'Восстанавливается до базового уровня перед стартом игровой ночи',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Доходность: '),
                    Text('${domain.income}'),
                    const SizedBox(width: 20),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () =>
                          _showTransferHungerDialog(context, domain.income),
                      tooltip: 'Передать пункты голода',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
