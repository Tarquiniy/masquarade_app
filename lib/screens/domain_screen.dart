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
  final DomainModel domain;

  const DomainScreen({super.key, required this.domain});

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

      if (await Geolocator.isLocationServiceEnabled()) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        );
        setState(() => _position = pos);
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
    
    // Загружаем домен при инициализации
    context.read<DomainBloc>().add(LoadUserDomain(widget.domain.id.toString()));
  }

  void _checkNightReset() {
    final now = DateTime.now();
    if (_lastNightReset == null || now.day != _lastNightReset!.day) {
      if (now.hour >= 20) {
        setState(() {
          _violationsCountTonight = 0;
          _lastNightReset = now;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.domain.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _isLoadingLocation ? null : _centerOnUser,
            tooltip: 'Центрировать на моём местоположении',
          ),
        ],
      ),
      body: BlocListener<DomainBloc, DomainState>(
        listener: (context, state) {
          if (state is DomainError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: _buildDomainContent(context),
      ),
    );
  }

  Widget _buildDomainContent(BuildContext context) {
    final center = widget.domain.boundaryPoints.isNotEmpty
        ? widget.domain.boundaryPoints.first
        : const LatLng(55.751244, 37.618423);

    return Column(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: BlocBuilder<MasqueradeBloc, MasqueradeState>(
            builder: (context, state) {
              List<ViolationModel> violations = [];
              
              if (state is ViolationsLoaded) {
                violations = state.violations
                    .where((v) => v.domainId == widget.domain.id)
                    .toList();
              }

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
                      _currentZoom = 13.0;
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.masquerade.app',
                    ),
                    if (widget.domain.boundaryPoints.isNotEmpty)
                      PolygonLayer(
                        polygons: [
                          Polygon(
                            points: widget.domain.boundaryPoints,
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
                                  onTap: () => _onViolationTap(context, v),
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    widget.domain.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (widget.domain.isNeutral)
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
                const Text(
                  'Статистика домена',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildDomainStatCard(context),
                const SizedBox(height: 20),
                const Text(
                  'Управление доменом',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildDomainControls(context),
                const SizedBox(height: 20),
                const Text(
                  'Нарушения маскарада',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Нарушений сегодня: $_violationsCountTonight/${widget.domain.securityLevel}',
                  style: TextStyle(
                    color: _violationsCountTonight >= widget.domain.securityLevel
                        ? Colors.red
                        : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _buildViolationsList(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDomainStatCard(BuildContext context) {
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
                  color: widget.domain.securityLevel > 0 ? Colors.blue : Colors.grey,
                  title: 'Защищенность',
                  value: widget.domain.securityLevel.toString(),
                ),
                const SizedBox(width: 15),
                _buildStatItem(
                  icon: Icons.auto_awesome,
                  color: widget.domain.totalInfluence > 0
                      ? Colors.purple
                      : Colors.grey,
                  title: 'Влияние',
                  value: widget.domain.totalInfluence.toString(),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                _buildStatItem(
                  icon: Icons.attach_money,
                  color: widget.domain.income > 0 ? Colors.green : Colors.grey,
                  title: 'Доход',
                  value: '${widget.domain.income}/день',
                ),
                const SizedBox(width: 15),
                _buildStatItem(
                  icon: Icons.warning,
                  color: widget.domain.openViolationsCount > 0
                      ? Colors.orange
                      : Colors.grey,
                  title: 'Нарушения',
                  value: widget.domain.openViolationsCount.toString(),
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

  Widget _buildDomainControls(BuildContext context) {
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
              onPressed: () => _transferDomain(context, widget.domain.id),
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

  Widget _buildViolationsList(BuildContext context) {
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
              .where((v) => v.domainId == widget.domain.id)
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
              return _buildViolationCard(context, v);
            },
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildViolationCard(BuildContext context, ViolationModel violation) {
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
        onTap: () => _onViolationTap(context, violation),
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

  void _onViolationTap(BuildContext context, ViolationModel v) {
    final profile = context.read<ProfileBloc>().state is ProfileLoaded
        ? (context.read<ProfileBloc>().state as ProfileLoaded).profile
        : null;

    if (profile == null) return;

    if (v.status == ViolationStatus.open) {
      setState(() {
        _violationsCountTonight++;
      });
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
              const SizedBox(height: 10),
              Text(
                'Нарушений сегодня: $_violationsCountTonight/${widget.domain.securityLevel}',
                style: TextStyle(
                  color: _violationsCountTonight >= widget.domain.securityLevel
                      ? Colors.red
                      : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Общее влияние домена: ${widget.domain.totalInfluence}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          if (v.canBeRevealed && !v.isRevealed)
            TextButton.icon(
              onPressed: () {
                if (widget.domain.totalInfluence < v.costToReveal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Недостаточно влияния для раскрытия. '
                        'Требуется: ${v.costToReveal}, '
                        'Влияние домена: ${widget.domain.totalInfluence}',
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
            ),
          if (v.canBeClosed)
            TextButton.icon(
              onPressed: () {
                if (widget.domain.totalInfluence < v.costToClose) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Влияния недостаточно для закрытия. '
                        'Требуется: ${v.costToClose}, '
                        'Влияние домена: ${widget.domain.totalInfluence}',
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
              context.read<DomainBloc>().add(LoadDomains());
            },
            child: const Text('Да'),
          ),
        ],
      ),
    );
  }
}

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