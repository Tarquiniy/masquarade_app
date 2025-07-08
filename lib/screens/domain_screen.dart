import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_event.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/profile/profile_bloc.dart';
import '../blocs/masquerade/masquerade_bloc.dart';
import '../models/domain_model.dart';
import '../models/profile_model.dart';
import '../models/violation_model.dart';
import '../repositories/supabase_repository.dart';
import 'masquerade_violation_screen.dart';

class DomainScreen extends StatefulWidget {
  const DomainScreen({super.key});

  @override
  State<DomainScreen> createState() => _DomainScreenState();
}

class _DomainScreenState extends State<DomainScreen> {
  late final MapController _mapController;
  late final SupabaseRepository _repository;

  Position? _position;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _repository = RepositoryProvider.of<SupabaseRepository>(context);
    _initLocation();
    context.read<DomainBloc>().add(RefreshDomains());
    context.read<MasqueradeBloc>().add(LoadViolations());
  }

  Future<void> _initLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever)
      return;

    final pos = await Geolocator.getCurrentPosition();
    setState(() => _position = pos);
  }

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ProfileBloc>().state;
    final domainState = context.watch<DomainBloc>().state;
    final violationState = context.watch<MasqueradeBloc>().state;

    if (profileState is! ProfileLoaded || domainState is! DomainsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = profileState.profile;

    final domain = domainState.domains.firstWhere(
      (d) => d.ownerId == profile.id,
      orElse: () => DomainModel(
        id: -1,
        name: '',
        latitude: 0,
        longitude: 0,
        boundaryPoints: [],
        isNeutral: true,
        openViolationsCount: 0,
        ownerId: 'нет',
      ),
    );

    if (domain.id == -1) {
      return const Scaffold(body: Center(child: Text('У вас нет домена')));
    }

    final violations = violationState is ViolationsLoaded
        ? violationState.violations
              .where((v) => v.domainId == domain.id)
              .toList()
        : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(domain.name),
        backgroundColor: const Color(0xFFff2e63),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 220,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: LatLng(domain.latitude, domain.longitude),
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.masquerade.app',
                ),
                if (domain.boundaryPoints.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: domain.boundaryPoints,
                        borderColor: const Color(0xFFff2e63),
                        color: const Color(0xFFff2e63).withOpacity(0.3),
                        borderStrokeWidth: 3,
                      ),
                    ],
                  ),
                if (violations.isNotEmpty)
                  MarkerLayer(
                    markers: violations.map((v) {
                      final color = v.status == ViolationStatus.open
                          ? Colors.amber
                          : Colors.teal;
                      return Marker(
                        point: LatLng(v.latitude, v.longitude),
                        width: 30,
                        height: 30,
                        child: Icon(Icons.location_pin, color: color, size: 30),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: profile.isHungry && _position != null
                        ? () {
                            context.read<MasqueradeBloc>().add(
                              StartHunt(
                                isDomainOwner: true,
                                domainId: domain.id,
                                position: _position!,
                              ),
                            );
                          }
                        : null,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFff2e63),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Охотиться'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MasqueradeViolationScreen(profile: profile),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFff2e63),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Нарушить Маскарад'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        _showTransferDomainDialog(context, domain.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFff2e63),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Передать домен'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text('Защищённость ${domain.securityLevel}')),
                Expanded(child: Text('Доходность ${domain.income}')),
                Expanded(child: Text('Влияние ${domain.influenceLevel}')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    _showTransferHungerDialog(context, profile, domain.income),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFff2e63),
                ),
                child: const Text('Передать кровь'),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.lightBlue,
            child: const Center(
              child: Text(
                'НАРУШЕНИЯ МАСКАРАДА В МОЕМ ДОМЕНЕ',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: violations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final v = violations[index];
                return ListTile(
                  tileColor: v.status == ViolationStatus.open
                      ? const Color(0xFFff2e63).withOpacity(0.1)
                      : Colors.teal.withOpacity(0.1),
                  title: Text('Нарушение маскарада №${v.id}'),
                  subtitle: Text(
                    v.createdAt.toLocal().toString().substring(11, 16),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showTransferDomainDialog(BuildContext context, int domainId) async {
    final profiles = await _repository.getAllProfiles();
    final currentId =
        (context.read<ProfileBloc>().state as ProfileLoaded).profile.id;
    final candidates = profiles.where((p) => p.id != currentId).toList();
    String? selectedId;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Передать домен'),
        content: DropdownButtonFormField<String>(
          items: candidates
              .map(
                (p) =>
                    DropdownMenuItem(value: p.id, child: Text(p.characterName)),
              )
              .toList(),
          onChanged: (value) => selectedId = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedId == null) return;
              await _repository.transferDomain(
                domainId.toString(),
                selectedId!,
              );
              if (mounted) {
                context.read<DomainBloc>().add(RefreshDomains());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Передать'),
          ),
        ],
      ),
    );
  }

  void _showTransferHungerDialog(
    BuildContext context,
    ProfileModel profile,
    int maxAmount,
  ) async {
    final profiles = await _repository.getAllProfiles();
    final candidates = profiles.where((p) => p.id != profile.id).toList();

    int amount = 1;
    String? selectedId;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Передача крови'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: amount > 1
                        ? () => setState(() => amount--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Text('$amount'),
                  IconButton(
                    onPressed: amount < maxAmount
                        ? () => setState(() => amount++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Получатель'),
                items: candidates
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.characterName),
                      ),
                    )
                    .toList(),
                onChanged: (val) => selectedId = val,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedId == null) return;
                await _repository.transferHunger(
                  fromUserId: profile.id,
                  toUserId: selectedId!,
                  amount: amount,
                );
                if (context.mounted) Navigator.pop(ctx);
              },
              child: const Text('Передать'),
            ),
          ],
        ),
      ),
    );
  }
}
