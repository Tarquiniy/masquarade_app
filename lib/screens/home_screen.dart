import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';

import '../models/profile_model.dart';
import '../models/domain_model.dart';
import '../models/violation_model.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_event.dart';
import '../blocs/domain/domain_state.dart';

import '../blocs/masquerade/masquerade_bloc.dart';
import 'violation_detail_screen.dart';
import 'profile_screen.dart';
import 'masquerade_violation_screen.dart';
import 'domain_screen.dart';
import '../utils/debug_telegram.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is ProfileInitial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is ProfileLoaded) {
          final profile = state.profile;
          context.read<DomainBloc>().add(RefreshDomains(profile));
          sendDebugToTelegram('✅ HomeScreen: профиль загружен: ${profile.id}');
          return _HomeScreenContent(profile: profile);
        }

        return const Scaffold(
          body: Center(child: Text('Неизвестное состояние профиля')),
        );
      },
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  final ProfileModel profile;

  const _HomeScreenContent({required this.profile});

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent> {
  Position? _position;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initLocation();
    context.read<MasqueradeBloc>().add(LoadViolations());
  }

  Future<void> _initLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
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

  void _onHunt() {
    final domainState = context.read<DomainBloc>().state;
    if (_position == null || domainState is! DomainsLoaded) return;

    final currentDomain = _findDomainAtPosition(domainState.domains);

    if (currentDomain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось определить территорию')),
      );
      return;
    }

    context.read<MasqueradeBloc>().add(
      StartHunt(
        isDomainOwner: currentDomain.ownerId == widget.profile.id,
        domainId: currentDomain.id,
        position: _position!,
      ),
    );
  }

  DomainModel? _findDomainAtPosition(List<DomainModel> domains) {
    for (final domain in domains) {
      if (!domain.isNeutral &&
          domain.isPointInside(_position!.latitude, _position!.longitude)) {
        return domain;
      }
    }

    // Найти нейтральную зону, если нет других
    final neutral = domains.where((d) => d.isNeutral);
    if (neutral.isNotEmpty) return neutral.first;

    return null; // если вообще ничего не нашли
  }

  void _openProfileScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(profile: widget.profile)),
    );
  }

  void _openDomainScreen() {
    context.read<DomainBloc>().add(RefreshDomains(widget.profile));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<MasqueradeBloc>(),
          child: const DomainScreen(),
        ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Главная'),
        actions: [
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.profile.isHungry ? _onHunt : null,
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
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openDomainScreen,
                    icon: const Icon(Icons.location_city),
                    label: const Text('Мой домен'),
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
