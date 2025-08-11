import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/blocs/domain/domain_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_state.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/screens/domain_screen.dart';

class DomainsScreen extends StatelessWidget {
  const DomainsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои Домены')),
      body: BlocBuilder<ProfileBloc, ProfileState>(
        builder: (context, profileState) {
          if (profileState is! ProfileLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          return BlocBuilder<DomainBloc, DomainState>(
            builder: (context, domainState) {
              if (domainState is DomainsLoaded) {
                final profile = profileState.profile;
                final userDomains = domainState.domains
                    .where((domain) => profile.domainIds.contains(domain.id))
                    .toList();

                if (userDomains.isEmpty) {
                  return const Center(child: Text('У вас пока нет доменов'));
                }

                return ListView.builder(
                  itemCount: userDomains.length,
                  itemBuilder: (context, index) {
                    final domain = userDomains[index];
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        leading: const Icon(Icons.castle),
                        title: Text(domain.name),
                        subtitle: Text('Влияние: ${domain.totalInfluence}'),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DomainScreen(domain: domain),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              }

              return const Center(child: CircularProgressIndicator());
            },
          );
        },
      ),
    );
  }
}