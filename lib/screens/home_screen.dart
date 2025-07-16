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
        const SnackBar(
          content: Text('Не удалось определить территорию'),
          backgroundColor: Colors.orange,
        ),
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

  // Функция для получения иконки клана
  IconData _getClanIcon(String clan) {
    switch (clan.toLowerCase()) {
      case 'ventrue':
        return Icons.coronavirus; // Корона
      case 'brujah':
        return Icons.flash_on; // Молния
      case 'toreador':
        return Icons.brush; // Кисть
      case 'malkavian':
        return Icons.psychology; // Мозг
      case 'nosferatu':
        return Icons.visibility_off; // Скрытость
      case 'tremere':
        return Icons.auto_awesome; // Магия
      case 'gangrel':
        return Icons.pets; // Зверь
      default:
        return Icons.question_mark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        if (profileState is! ProfileLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = profileState.profile;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Маскарад',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: Colors.white,
                fontFamily: 'Gothic',
                shadows: [
                  Shadow(
                    blurRadius: 4.0,
                    color: Colors.black,
                    offset: Offset(2.0, 2.0),
                  ),
                ],
              ),
            ),
            centerTitle: true,
            backgroundColor: Color(0xFF4A0000), // Тёмно-бордовый
            elevation: 0,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A0000), Color(0xFF2A0000)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.8),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.account_circle, color: Colors.amber[200]),
                onPressed: _openProfileScreen,
                tooltip: 'Профиль',
              ),
              IconButton(
                icon: Icon(Icons.my_location, color: Colors.amber[200]),
                onPressed: _isLoadingLocation ? null : _initLocation,
                tooltip: 'Центрировать на моём местоположении',
              ),
            ],
          ),
          body: BlocListener<MasqueradeBloc, MasqueradeState>(
            listener: (context, state) {
              // Показываем уведомления о результатах охоты
              if (state is HuntCompleted) {
                if (state.violationOccurred) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Охота успешна! Но создано нарушение маскарада '
                        '(стоимость закрытия: ${state.costToClose} влияния)',
                      ),
                      backgroundColor: Colors.amber[800],
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Охота прошла успешно! Голод утолён'),
                      backgroundColor: Color(0xFF006400),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }

              // Уведомление о созданном нарушении
              if (state is ViolationReportedSuccessfully) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Нарушение маскарада успешно создано!'),
                    backgroundColor: Color(0xFF8B0000),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: BlocListener<DomainBloc, DomainState>(
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
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.masquerade.app',
                      ),
                      if (_currentUserDomain != null &&
                          _currentUserDomain!.boundaryPoints.isNotEmpty)
                        PolygonLayer(
                          polygons: [
                            Polygon(
                              points: _currentUserDomain!.boundaryPoints,
                              color: Color(0xFF8B0000).withOpacity(0.3),
                              borderColor: Color(0xFFD4AF37),
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
                              width: 48,
                              height: 48,
                              child: Icon(
                                _getClanIcon(profile.clan),
                                color: Color(0xFFD4AF37),
                                size: 48,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (_isLoadingLocation)
                    Center(
                      child: Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFFD4AF37),
                          ),
                        ),
                      ),
                    ),
                  // Статус-бар с информацией о персонаже
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: _buildCharacterStatusBar(profile),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    icon: Icons.restaurant,
                    label: 'Охотиться',
                    color: Color(0xFF8B0000),
                    onPressed: profile.isHungry ? _onHunt : null,
                  ),
                  _buildActionButton(
                    icon: Icons.warning,
                    label: 'Нарушить',
                    color: Color(0xFF4A0000),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BlocProvider.value(
                            value: context.read<MasqueradeBloc>(),
                            child: MasqueradeViolationScreen(profile: profile),
                          ),
                        ),
                      );
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.location_city,
                    label: 'Домен',
                    color: Color(0xFF2A0000),
                    onPressed: _openDomainScreen,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Виджет статус-бара персонажа
  Widget _buildCharacterStatusBar(ProfileModel profile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Color(0xFF1A1A1A).withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Color(0xFFD4AF37).withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Color(0xFFD4AF37), width: 2),
                color: Colors.black.withOpacity(0.5),
              ),
              child: Icon(
                _getClanIcon(profile.clan),
                color: Color(0xFFD4AF37),
                size: 30,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.characterName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                      fontFamily: 'Gothic',
                      shadows: [
                        Shadow(
                          blurRadius: 2.0,
                          color: Colors.black,
                          offset: Offset(1.0, 1.0),
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${profile.clan}, ${profile.sect}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber[200],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildStatusIndicator(
              icon: Icons.favorite,
              value: profile.hunger,
              color: Color(0xFF8B0000),
              max: 5,
            ),
            const SizedBox(width: 8),
            _buildStatusIndicator(
              icon: Icons.coronavirus,
              value: profile.influence,
              color: Color(0xFFD4AF37),
              max: 10,
            ),
          ],
        ),
      ),
    );
  }

  // Виджет индикатора статуса
  Widget _buildStatusIndicator({
    required IconData icon,
    required int value,
    required Color color,
    required int max,
  }) {
    return Tooltip(
      message: '${value}/$max',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Виджет кнопки действия
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Color(0xFFD4AF37), size: 24),
        label: Text(
          label,
          style: TextStyle(
            color: Color(0xFFD4AF37),
            fontWeight: FontWeight.bold,
            fontSize: 14,
            fontFamily: 'Gothic',
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.9),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: BorderSide(color: Color(0xFFD4AF37), width: 1.5),
          ),
          elevation: 5,
          shadowColor: Colors.black.withOpacity(0.5),
        ),
      ),
    );
  }
}
