import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/blocs/domain/domain_event.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/profile/profile_bloc.dart';
import '../blocs/masquerade/masquerade_bloc.dart';

import '../models/domain_model.dart';
import '../models/profile_model.dart';
import '../models/violation_model.dart';
import '../utils/debug_telegram.dart';

class DomainScreen extends StatefulWidget {
  const DomainScreen({super.key});

  @override
  State<DomainScreen> createState() => _DomainScreenState();
}

class _DomainScreenState extends State<DomainScreen> {
  final MapController _mapController = MapController();
  Position? _position;
  bool _isLoadingLocation = false;
  double _currentZoom = 13.0;
  int _violationsCountTonight = 0;
  DateTime? _lastNightReset;

  Future<void> _centerOnUser() async {
    setState(() => _isLoadingLocation = true);

    try {
      // Проверка и запрос разрешений
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      // Получение текущей позиции
      if (await Geolocator.isLocationServiceEnabled()) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
        setState(() => _position = pos);

        // Центрирование карты на пользователе
        _mapController.move(LatLng(pos.latitude, pos.longitude), _currentZoom);
      }
    } catch (e) {
      print("Ошибка получения местоположения: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Не удалось получить позицию'),
          backgroundColor: Colors.red[700],
        ),
      );
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _centerOnUser();
    _checkNightReset();
  }

  void _checkNightReset() {
    final now = DateTime.now();
    // Сбрасываем счетчик нарушений в 20:00 каждый день
    if (_lastNightReset == null || now.day != _lastNightReset!.day) {
      if (now.hour >= 20) {
        setState(() {
          _violationsCountTonight = 0;
          _lastNightReset = now;
        });
      }
    }
  }

  Future<void> _handleDomainNeutralization(DomainModel domain) async {
    if (domain.isNeutral) return;

    if (_violationsCountTonight >= domain.securityLevel) {
      final bloc = context.read<DomainBloc>();
      final repository = bloc.repository;

      try {
        // Помечаем домен как нейтральный в базе данных
        await repository.client
            .from('domains')
            .update({'isNeutral': true, 'ownerId': null})
            .eq('id', domain.id);

        // Обновляем состояние
        bloc.add(
          RefreshDomains(
            (context.read<ProfileBloc>().state as ProfileLoaded).profile,
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Домен "${domain.name}" стал нейтральным из-за нарушений',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        print('Ошибка нейтрализации домена: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой Домен'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _isLoadingLocation ? null : _centerOnUser,
            tooltip: 'Центрировать на моём местоположении',
          ),
        ],
      ),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, profileState) {
          return BlocBuilder<DomainBloc, DomainState>(
            builder: (context, domainState) {
              // Показываем индикатор загрузки пока данные не готовы
              if (profileState is! ProfileLoaded ||
                  domainState is! DomainsLoaded) {
                return const Center(child: CircularProgressIndicator());
              }

              final profile = profileState.profile;
              context.read<MasqueradeBloc>().add(LoadViolations());

              return Stack(
                children: [
                  _buildDomainContent(context, profile, domainState.domains),
                  if (_isLoadingLocation)
                    const Center(child: CircularProgressIndicator()),
                ],
              );
            },
          );
        },
      ),
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

    // Если у пользователя нет домена
    if (userDomain.id == -1) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_city, size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              Text(
                'У вас пока нет своего домена',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              const Text(
                'Домен - это территория под вашим контролем, где вы можете охотиться с меньшим риском нарушить Маскарад.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Обратитесь к рассказчику, чтобы получить домен',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.help),
                label: const Text('Как получить домен?'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Проверяем, не нужно ли нейтрализовать домен
    _handleDomainNeutralization(userDomain);

    final center = userDomain.boundaryPoints.isNotEmpty
        ? userDomain.boundaryPoints.first
        : const LatLng(55.751244, 37.618423);

    return Column(
      children: [
        // Карта домена
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: BlocBuilder<MasqueradeBloc, MasqueradeState>(
            builder: (context, state) {
              final violations = (state is ViolationsLoaded)
                  ? state.violations
                        .where((v) => v.domainId == userDomain.id)
                        .toList()
                  : <ViolationModel>[];

              return ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 13,
                    interactionOptions: const InteractionOptions(
                      flags: ~InteractiveFlag.doubleTapDragZoom,
                    ),
                    onMapReady: () {
                      // Сохраняем начальный уровень зума
                      _currentZoom = 13.0;
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.masquerade.app',
                    ),
                    if (userDomain.boundaryPoints.isNotEmpty)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: userDomain.boundaryPoints,
                            color: Colors.blue.withOpacity(0.25),
                            borderColor: Colors.blue,
                            borderStrokeWidth: 3,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        ...violations
                            .map(
                              (v) => Marker(
                                point: LatLng(v.latitude, v.longitude),
                                width: 40,
                                height: 40,
                                child: GestureDetector(
                                  onTap: () =>
                                      _onViolationTap(context, v, userDomain),
                                  child: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.red,
                                    size: 32,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        if (_position != null)
                          Marker(
                            point: LatLng(
                              _position!.latitude,
                              _position!.longitude,
                            ),
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.deepPurple,
                              size: 48,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Информация о домене
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок
                Center(
                  child: Text(
                    userDomain.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Статус домена
                if (userDomain.isNeutral)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          'Нейтральная территория',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                const Divider(),

                // Статистика домена
                const Text(
                  'Статистика домена',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildDomainStatCard(context, userDomain, profile),
                const SizedBox(height: 20),

                // Управление доменом
                const Text(
                  'Управление доменом',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildDomainControls(context, userDomain),
                const SizedBox(height: 20),

                // Нарушения маскарада
                const Text(
                  'Нарушения маскарада',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нарушений сегодня: $_violationsCountTonight/${userDomain.securityLevel}',
                  style: TextStyle(
                    color: _violationsCountTonight >= userDomain.securityLevel
                        ? Colors.red
                        : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _buildViolationsList(context, profile, userDomain),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDomainStatCard(
    BuildContext context,
    DomainModel domain,
    ProfileModel profile,
  ) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.security,
                  color: domain.securityLevel > 0 ? Colors.blue : Colors.grey,
                  title: 'Защищенность',
                  value: domain.securityLevel.toString(),
                ),
                const SizedBox(width: 15),
                _buildStatItem(
                  icon: Icons.auto_awesome,
                  color: profile.totalInfluence > 0
                      ? Colors.purple
                      : Colors.grey,
                  title: 'Влияние',
                  value: profile.totalInfluence.toString(),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.attach_money,
                  color: domain.income > 0 ? Colors.green : Colors.grey,
                  title: 'Доход',
                  value: '${domain.income}/день',
                ),
                const SizedBox(width: 15),
                _buildStatItem(
                  icon: Icons.warning,
                  color: domain.openViolationsCount > 0
                      ? Colors.orange
                      : Colors.grey,
                  title: 'Нарушения',
                  value: domain.openViolationsCount.toString(),
                ),
              ],
            ),
            const SizedBox(height: 15),
            // ДОБАВЛЯЕМ СТРОКУ С ВЛИЯНИЕМ ИГРОКА
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.person,
                  color: profile.influence > 0
                      ? Colors.deepPurple
                      : Colors.grey,
                  title: 'Ваше влияние',
                  value: profile.influence.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainControls(BuildContext context, DomainModel domain) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: () => _transferDomain(context, domain.id),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Передать домен'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blueGrey[50],
                foregroundColor: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Передайте домен другому игроку',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViolationsList(
    BuildContext context,
    ProfileModel profile,
    DomainModel domain,
  ) {
    return BlocBuilder<MasqueradeBloc, MasqueradeState>(
      builder: (context, state) {
        if (state is ViolationsLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is ViolationsError) {
          return Center(
            child: Text(
              state.message,
              style: TextStyle(color: Colors.red[700]),
            ),
          );
        }

        if (state is ViolationsLoaded) {
          final violationsInDomain = state.violations
              .where((v) => v.domainId == domain.id)
              .toList();

          if (violationsInDomain.isEmpty) {
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.verified_user,
                      size: 60,
                      color: Colors.green[400],
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      'Нарушений не обнаружено',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'На территории вашего домена всё спокойно',
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: violationsInDomain.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (_, idx) {
              final v = violationsInDomain[idx];
              return _buildViolationCard(context, v, profile);
            },
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildViolationCard(
    BuildContext context,
    ViolationModel violation,
    ProfileModel profile,
  ) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (violation.status) {
      case ViolationStatus.open:
        statusColor = Colors.orange;
        statusIcon = Icons.warning_amber;
        statusText = 'Открыто';
        break;
      case ViolationStatus.closed:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Закрыто';
        break;
      case ViolationStatus.revealed:
        statusColor = Colors.purple;
        statusIcon = Icons.visibility;
        statusText = 'Раскрыто';
        break;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          if (violation.status == ViolationStatus.open ||
              violation.canBeClosed ||
              violation.canBeRevealed) {
            _onViolationTap(context, violation, null);
          } else {
            _showViolationStatusInfo(context, violation);
          }
        },
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(statusIcon, size: 18, color: statusColor),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTimeAgo(violation.createdAt),
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(violation.description, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
              if (violation.violatorName != null)
                Text(
                  'Нарушитель: ${violation.violatorName}',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onViolationTap(
    BuildContext context,
    ViolationModel v,
    DomainModel? domain,
  ) {
    final profile =
        (context.read<ProfileBloc>().state as ProfileLoaded).profile;

    // Обновляем счетчик нарушений
    if (domain != null && v.status == ViolationStatus.open) {
      setState(() {
        _violationsCountTonight++;
      });
      _handleDomainNeutralization(domain);
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Нарушение Маскарада'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(v.description),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(
                    '${v.latitude.toStringAsFixed(4)}, ${v.longitude.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(
                    _formatDateTime(v.createdAt),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              if (domain != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Нарушений сегодня: $_violationsCountTonight/${domain.securityLevel}',
                  style: TextStyle(
                    color: _violationsCountTonight >= domain.securityLevel
                        ? Colors.red
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Общее влияние домена: ${profile.totalInfluence}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (v.canBeRevealed && _isWithin24h(v) && !v.isRevealed)
            TextButton.icon(
              onPressed: () {
                final domain = context.read<DomainBloc>().state is DomainsLoaded
                    ? (context.read<DomainBloc>().state as DomainsLoaded)
                          .domains
                          .firstWhere((d) => d.id == v.domainId)
                    : null;

                if (domain == null) return;

                final totalInfluence = profile.totalInfluence;
                if (profile.influence < v.costToReveal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Недостаточно влияния для раскрытия. '
                        'Требуется: ${v.costToReveal}, '
                        'Ваше влияние: ${profile.influence}, '
                        'Общее влияние домена: $totalInfluence',
                      ),
                    ),
                  );
                  Navigator.pop(context);
                  return;
                }

                context.read<MasqueradeBloc>().add(
                  RevealViolator(violationId: v.id),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Вы узнали нарушителя')),
                );
              },
              icon: const Icon(Icons.visibility, size: 20),
              label: Text('Узнать нарушителя (${v.costToReveal} влияния)'),
            )
          else if (!v.canBeRevealed)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Нарушитель уже раскрыт',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          if (v.canBeClosed)
            TextButton.icon(
              onPressed: () {
                final domain = context.read<DomainBloc>().state is DomainsLoaded
                    ? (context.read<DomainBloc>().state as DomainsLoaded)
                          .domains
                          .firstWhere((d) => d.id == v.domainId)
                    : null;

                if (domain == null) return;

                final totalInfluence = profile.totalInfluence;
                if (profile.influence < v.costToClose) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Влияния недостаточно для закрытия. '
                        'Требуется: ${v.costToClose}, '
                        'Ваше влияние: ${profile.influence}, '
                        'Общее влияние домена: $totalInfluence',
                      ),
                    ),
                  );
                  Navigator.pop(context);
                  return;
                }

                context.read<MasqueradeBloc>().add(
                  CloseViolation(violationId: v.id),
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Нарушение успешно закрыто')),
                );
              },
              icon: const Icon(Icons.check_circle, size: 20),
              label: Text('Закрыть нарушение (${v.costToClose} влияния)'),
            )
          else
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Нарушение уже закрыто',
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  void _showViolationStatusInfo(
    BuildContext context,
    ViolationModel violation,
  ) {
    String message;
    if (violation.isClosed) {
      message = 'Вы уже закрыли это нарушение';
    } else if (violation.isRevealed) {
      message = 'Вы уже узнали нарушителя';
    } else {
      message = 'Срок для действий по этому нарушению истёк';
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Нарушение Маскарада'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
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
                Text(
                  'Доступно: $maxHunger пунктов',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: hungerToTransfer > 1
                          ? () => setState(() => hungerToTransfer--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Container(
                      width: 50,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$hungerToTransfer',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    IconButton(
                      onPressed: hungerToTransfer < maxHunger
                          ? () => setState(() => hungerToTransfer++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      _chooseHungerRecipient(context, hungerToTransfer),
                  child: const Text('Выбрать получателя'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size(double.infinity, 50),
                  ),
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
                subtitle: Text(p.clan),
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
    final profile =
        (context.read<ProfileBloc>().state as ProfileLoaded).profile;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтверждение передачи'),
        content: Text(
          'Вы хотите передать $amount пунктов голода игроку ${recipient.characterName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await context.read<DomainBloc>().repository.transferHunger(
                  fromUserId: profile.id,
                  toUserId: recipient.id,
                  amount: amount,
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Успешно передано $amount пунктов голода'),
                    backgroundColor: Colors.green,
                  ),
                );

                // Обновляем профиль получателя
                context.read<ProfileBloc>().add(
                  UpdateProfile(
                    recipient.copyWith(hunger: recipient.hunger + amount),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ошибка передачи: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Передать'),
          ),
        ],
      ),
    );
  }
}

// Вспомогательные функции
String _formatTimeAgo(DateTime date) {
  final now = DateTime.now();
  final difference = now.difference(date);

  if (difference.inMinutes < 1) return 'Только что';
  if (difference.inMinutes < 60) return '${difference.inMinutes} мин назад';
  if (difference.inHours < 24) return '${difference.inHours} ч назад';
  if (difference.inDays < 30) return '${difference.inDays} дн назад';

  return '${(difference.inDays / 30).floor()} мес назад';
}

String _formatDateTime(DateTime date) {
  return '${date.day}.${date.month}.${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
}

bool _isWithin24h(ViolationModel v) {
  final now = DateTime.now();
  return now.difference(v.createdAt).inHours <= 24;
}
