import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/blocs/domain/domain_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_event.dart';
import 'package:masquarade_app/blocs/domain/domain_state.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/screens/domain_screen.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DomainsScreen extends StatefulWidget {
  const DomainsScreen({super.key});

  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  final MapController _mapController = MapController();
  bool _isLoadingLocation = false;
  bool _isMapReady = false;
  Map<String, String> _ownerNames = {};
  Position? _currentPosition;
  List<DomainModel> _userDomains = [];
  StreamSubscription<List<DomainModel>>? _domainSubscription;
  late final SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _initPrefs().then((_) {
      _loadOwnerNames();
      _initLocation();
      _subscribeToDomainUpdates();
    });
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  void _subscribeToDomainUpdates() {
    final repository = context.read<DomainBloc>().repository;
    _domainSubscription = repository.domainsStream.listen((domains) {
      if (mounted) {
        setState(() {
          _updateUserDomains(domains);
        });
        _checkIfShouldCloseScreen(_userDomains);
      }
    });
  }

  Future<void> _initLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _currentPosition = position;
      });
      
      if (_isMapReady) {
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          15,
        );
      }
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка центрирования: $e');
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _loadOwnerNames() async {
    final players = await context.read<ProfileBloc>().getPlayers();
    setState(() {
      _ownerNames = { for (var p in players) p.id : p.characterName };
    });
  }

  Future<void> _centerOnLocation() async {
    if (!_isMapReady) {
      await Future.delayed(const Duration(milliseconds: 100));
      return _centerOnLocation();
    }
    
    setState(() => _isLoadingLocation = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        15,
      );
    } catch (e) {
      sendDebugToTelegram('❌ Ошибка центрирования: $e');
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  void _updateUserDomains(List<DomainModel> allDomains) {
    final profileState = context.read<ProfileBloc>().state;
    if (profileState is ProfileLoaded) {
      final profile = profileState.profile;
      _userDomains = allDomains
          .where((domain) => domain.ownerId == profile.id && 
                             !domain.isNeutral && 
                             domain.securityLevel > 0)
          .toList();
    }
  }

  void _checkIfShouldCloseScreen(List<DomainModel> userDomains) {
    if (userDomains.isEmpty && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _domainSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ProfileBloc>().state;

    if (profileState is! ProfileLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final profile = profileState.profile;

    return BlocListener<DomainBloc, DomainState>(
      listener: (context, state) {
        if (state is DomainsLoaded) {
          _updateUserDomains(state.domains);
          _checkIfShouldCloseScreen(_userDomains);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Мои Домены'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          actions: [
            IconButton(
              icon: _isLoadingLocation
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.my_location),
              onPressed: _isLoadingLocation ? null : _centerOnLocation,
              tooltip: 'Центрировать на моём местоположении',
            ),
          ],
        ),
        body: BlocBuilder<DomainBloc, DomainState>(
          builder: (context, domainState) {
            if (domainState is DomainInitial || domainState is DomainLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (domainState is DomainError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Ошибка загрузки доменов: ${domainState.message}'),
                    ElevatedButton(
                      onPressed: () => context.read<DomainBloc>().add(LoadDomains()),
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }

            if (domainState is DomainsLoaded) {
              final domains = domainState.domains;
              
              _updateUserDomains(domains);

              if (_userDomains.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.domain, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'У вас пока нет доменов',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Переданный вам домен появится здесь после перезагрузки страницы',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  SizedBox(
                    height: 300,
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentPosition != null
                            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                            : const LatLng(55.751244, 37.618423),
                        initialZoom: 13,
                        onMapReady: () {
                          setState(() => _isMapReady = true);
                          if (_currentPosition != null) {
                            _mapController.move(
                              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                              15,
                            );
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        ),
                        PolygonLayer(
                          polygons: [
                            for (final domain in _userDomains)
                              Polygon(
                                points: domain.boundaryPoints,
                                color: Colors.blue.withOpacity(0.3),
                                borderColor: Colors.blue,
                                borderStrokeWidth: 2,
                              ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            if (_currentPosition != null)
                              Marker(
                                point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                width: 40,
                                height: 40,
                                child: const Icon(
                                  Icons.person_pin_circle,
                                  color: Colors.blue,
                                  size: 40,
                                ),
                              ),
                            for (final domain in _userDomains)
                              Marker(
                                point: LatLng(domain.latitude, domain.longitude),
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () => _openDomain(context, domain, profile),
                                  child: const Icon(
                                    Icons.location_city,
                                    color: Colors.red,
                                    size: 40,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        context.read<DomainBloc>().add(LoadDomains());
                      },
                      child: ListView.builder(
                        itemCount: _userDomains.length,
                        itemBuilder: (context, index) {
                          final domain = _userDomains[index];
                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: InkWell(
                              onTap: () => _openDomain(context, domain, profile),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.castle, size: 36),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            domain.name,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Владелец: ${domain.ownerId.isNotEmpty ? _ownerNames[domain.ownerId] ?? domain.ownerId : 'Не назначен'}',
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                          Text(
                                            'Влияние: ${domain.influenceLevel} | Защита: ${domain.securityLevel}',
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward, size: 24),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            }

            return const Center(child: Text('Непредвиденное состояние'));
          },
        ),
      ),
    );
  }

  void _openDomain(BuildContext context, DomainModel domain, ProfileModel profile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DomainScreen(domain: domain, profile: profile),
      ),
    ).then((_) {
      context.read<DomainBloc>().add(LoadDomains());
    });
  }
}