import 'package:flutter/material.dart';
import '../models/domain_model.dart';

class DomainStatsCard extends StatelessWidget {
  final DomainModel domain;

  const DomainStatsCard({super.key, required this.domain});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[800],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Статистика Домена',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildStatRow('Защищенность', domain.securityLevel.toString()),
            _buildStatRow(
              'Влиятельность',
              '${domain.totalInfluence} (${domain.influenceLevel} + ${domain.adminInfluence})',
            ),
            _buildStatRow('Доходность', '${domain.income} пунктов голода'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
