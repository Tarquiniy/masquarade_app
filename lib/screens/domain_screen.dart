import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/profile/profile_bloc.dart';
import '../models/domain_model.dart';

class DomainScreen extends StatelessWidget {
  const DomainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ProfileBloc>().state;
    final domainState = context.watch<DomainBloc>().state;

    if (profileState is! ProfileLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = profileState.profile;

    if (domainState is! DomainsLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
      ),
    );

    if (domain.id == -1) {
      return const Scaffold(body: Center(child: Text('У вас нет домена')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Домен: ${domain.name}')),
      body: Column(
        children: [
          SizedBox(
            height: 220,
            child: FlutterMap(
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
                        borderColor: Colors.red,
                        color: Colors.red.withOpacity(0.3),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Доходность: ${domain.income} пунктов голода'),
                Text('Защищённость: ${domain.securityLevel}'),
                Text('Влияние: ${domain.influenceLevel}'),
                const SizedBox(height: 12),
                Text('Нарушений открыто: ${domain.openViolationsCount}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
