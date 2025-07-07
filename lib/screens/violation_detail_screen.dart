import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/models/profile_model.dart';
import '../../blocs/masquerade/masquerade_bloc.dart';
import '../../models/violation_model.dart';

class ViolationDetailScreen extends StatelessWidget {
  final ViolationModel violation;

  const ViolationDetailScreen({
    super.key,
    required this.violation,
    required ProfileModel profile,
  });

  @override
  Widget build(BuildContext context) {
    final profileState = context.watch<ProfileBloc>().state;

    if (profileState is! ProfileLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final profile = profileState.profile;
    final isOwner = profile.domain == violation.domainId.toString();

    return Scaffold(
      appBar: AppBar(title: const Text('Детали нарушения')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _buildInfoRow('Описание', violation.description),
            _buildInfoRow('Статус', _statusText(violation)),
            _buildInfoRow('Дата', violation.createdAt.toString()),
            _buildInfoRow('Потрачено голода', violation.hungerSpent.toString()),
            _buildInfoRow(
              'Стоимость закрытия',
              violation.costToClose.toString(),
            ),

            if (violation.isRevealed)
              _buildInfoRow(
                'Нарушитель',
                violation.violatorName ?? 'Неизвестно',
              ),

            if (violation.resolvedBy != null)
              _buildInfoRow('Закрыто пользователем', violation.resolvedBy!),

            const SizedBox(height: 32),

            if (isOwner && !violation.isClosed)
              ElevatedButton(
                onPressed: () {
                  // Проверка на null перед закрытием
                  if (violation.id != null) {
                    context.read<MasqueradeBloc>().add(
                      CloseViolation(violation.id!),
                    );
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ошибка: у нарушения нет ID'),
                      ),
                    );
                  }
                },
                child: const Text('Закрыть нарушение'),
              ),

            if (isOwner && !violation.isRevealed && violation.canBeRevealed)
              ElevatedButton(
                onPressed: () {
                  // Проверка на null перед раскрытием
                  if (violation.id != null) {
                    context.read<MasqueradeBloc>().add(
                      RevealViolator(violation.id!),
                    );
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ошибка: у нарушения нет ID'),
                      ),
                    );
                  }
                },
                child: const Text('Раскрыть нарушителя'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _statusText(ViolationModel v) {
    if (v.isRevealed) return 'Раскрыто';
    if (v.isClosed) return 'Закрыто';
    return 'Открыто';
  }
}
