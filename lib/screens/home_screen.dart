import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_event.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/masquerade/masquerade_bloc.dart';
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
  DomainModel? _currentUserDomain;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    context.read<MasqueradeBloc>().add(LoadViolations());
    _loadUserDomain();
  }

  Future<void> _initLocation() async {
    setState(() => _isLoadingLocation = true);

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
    }

    if (await Geolocator.isLocationServiceEnabled()) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
        setState(() {
          _position = pos;
          _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
        });
      } catch (e) {
        print("Ошибка получения местоположения: $e");
      }
    }

    setState(() => _isLoadingLocation = false);
  }

  void _loadUserDomain() {
    context.read<DomainBloc>().add(LoadCurrentUserDomain());
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

    final neutral = domains.where((d) => d.isNeutral);
    if (neutral.isNotEmpty) return neutral.first;

    return null;
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoadingLocation ? null : _initLocation,
          ),
        ],
      ),
      body: BlocListener<DomainBloc, DomainState>(
        listener: (context, state) {
          if (state is CurrentUserDomainLoaded) {
            setState(() {
              _currentUserDomain = state.domain;
            });
          }
        },
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _position != null
                    ? LatLng(_position!.latitude, _position!.longitude)
                    : const LatLng(55.751244, 37.618423),
                initialZoom: 13,
                interactionOptions: const InteractionOptions(
                  flags: ~InteractiveFlag.doubleTapDragZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.masquerade.app',
                ),
                if (_currentUserDomain != null &&
                    _currentUserDomain!.boundaryPoints.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _currentUserDomain!.boundaryPoints,
                        color: Colors.blue.withOpacity(0.3),
                        borderColor: Colors.blue,
                        borderStrokeWidth: 2,
                      ),
                    ],
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
            if (_isLoadingLocation)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: widget.profile.isHungry ? _onHunt : null,
              icon: const Icon(Icons.restaurant),
              label: const Text('Охотиться'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.warning),
              label: const Text('Нарушить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFe94560),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlocProvider.value(
                      value: context.read<MasqueradeBloc>(),
                      child: MasqueradeViolationScreen(profile: widget.profile),
                    ),
                  ),
                );
              },
            ),
            ElevatedButton.icon(
              onPressed: _openDomainScreen,
              icon: const Icon(Icons.location_city),
              label: const Text('Домен'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
