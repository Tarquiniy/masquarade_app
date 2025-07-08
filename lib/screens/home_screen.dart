import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/profile_model.dart';
import '../models/violation_model.dart';
import '../models/domain_model.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_event.dart';
import '../blocs/domain/domain_state.dart';

import '../blocs/masquerade/masquerade_bloc.dart';
import 'violation_detail_screen.dart';
import 'profile_screen.dart';
import 'masquerade_violation_screen.dart';
import 'domain_screen.dart';

class HomeScreen extends StatefulWidget {
  final ProfileModel profile;
  const HomeScreen({super.key, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Position? _position;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initLocation();
    context.read<MasqueradeBloc>().add(LoadViolations());
    context.read<DomainBloc>().add(LoadDomains());
  }

  Future<void> _initLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      final result = await Geolocator.requestPermission();
      if (result != LocationPermission.whileInUse &&
          result != LocationPermission.always) {
        return;
      }
    }

    if (!await Geolocator.isLocationServiceEnabled()) return;

    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _position = pos;
      if (_position != null) {
        _mapController.move(
          LatLng(_position!.latitude, _position!.longitude),
          13,
        );
      }
    });
  }

  void _onHunt(ProfileModel profile) {
    final domainState = context.read<DomainBloc>().state;
    if (_position == null || domainState is! DomainsLoaded) return;

    final currentDomain = _findDomainAtPosition(
      domainState.domains,
      _position!,
    );

    if (currentDomain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось определить территорию')),
      );
      return;
    }

    context.read<MasqueradeBloc>().add(
      StartHunt(
        isDomainOwner: currentDomain.ownerId == profile.id,
        domainId: currentDomain.id,
        position: _position!,
      ),
    );
  }

  DomainModel? _findDomainAtPosition(
    List<DomainModel> domains,
    Position position,
  ) {
    try {
      for (final domain in domains) {
        if (!domain.isNeutral &&
            domain.isPointInside(position.latitude, position.longitude)) {
          return domain;
        }
      }

      return domains.firstWhere(
        (d) => d.isNeutral,
        orElse: () => DomainModel(
          id: -1,
          name: 'Нейтральная зона',
          latitude: 0,
          longitude: 0,
          boundaryPoints: [],
          isNeutral: true,
          openViolationsCount: 0,
          ownerId: 'нет',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _openProfileScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ProfileScreen(profile: widget.profile), // Убрали параметр domain
      ),
    );
  }

  String _violationStatusText(ViolationStatus status) {
    switch (status) {
      case ViolationStatus.open:
        return 'Открыто';
      case ViolationStatus.closed:
        return 'Закрыто';
      case ViolationStatus.revealed:
        return 'Раскрыто';
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final domainState = context.watch<DomainBloc>().state;

    // Проверяем, является ли пользователь владельцем домена
    bool isDomainOwner = false;
    if (domainState is DomainsLoaded) {
      isDomainOwner = domainState.domains.any((d) => d.ownerId == profile.id);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
          if (isDomainOwner) // Показываем кнопку только владельцам
            IconButton(
              icon: const Icon(Icons.location_city),
              tooltip: 'Мой домен',
              onPressed: () {
                context.read<DomainBloc>().add(RefreshDomains());
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DomainScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: _openProfileScreen,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _position != null
                    ? LatLng(_position!.latitude, _position!.longitude)
                    : const LatLng(55.751244, 37.618423),
                initialZoom: 13,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.masquerade.app',
                ),
                if (domainState is DomainsLoaded)
                  PolygonLayer(
                    polygons: domainState.domains
                        .where((d) => d.boundaryPoints.length >= 3)
                        .map((domain) {
                          Color color;
                          if (domain.ownerId == profile.id) {
                            color = Colors.blue;
                          } else if (domain.isNeutral) {
                            color = Colors.grey;
                          } else {
                            color = Colors.red;
                          }

                          return Polygon(
                            points: domain.boundaryPoints,
                            borderColor: color,
                            borderStrokeWidth: 2,
                            color: color.withOpacity(0.3),
                          );
                        })
                        .toList(),
                  ),
                if (_position != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          _position!.latitude,
                          _position!.longitude,
                        ),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: profile.isHungry ? () => _onHunt(profile) : null,
                    icon: const Icon(Icons.restaurant),
                    label: const Text('Охотиться'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.warning),
                    label: const Text('Нарушить маскарад'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFe94560),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: context.read<MasqueradeBloc>(),
                            child: MasqueradeViolationScreen(
                              profile: widget.profile,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Недавние нарушения',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: BlocBuilder<MasqueradeBloc, MasqueradeState>(
              builder: (context, state) {
                if (state is ViolationsLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is ViolationsLoaded) {
                  final list = state.violations;
                  if (list.isEmpty) {
                    return const Center(child: Text('Нарушений нет'));
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final v = list[index];
                      return ListTile(
                        title: Text(v.description),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_violationStatusText(v.status)),
                            Text('Голод: ${v.hungerSpent}'),
                            if (v.violatorName != null)
                              Text('Нарушитель: ${v.violatorName}'),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ViolationDetailScreen(violation: v),
                            ),
                          );
                        },
                      );
                    },
                  );
                } else if (state is ViolationsError) {
                  return Center(child: Text(state.message));
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
