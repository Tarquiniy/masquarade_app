import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/blocs/masquerade/masquerade_bloc.dart';
import 'package:masquarade_app/models/violation_model.dart';

class ViolationsScreen extends StatelessWidget {
  const ViolationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    context.read<MasqueradeBloc>().add(LoadViolations());

    return Scaffold(
      appBar: AppBar(title: const Text('Нарушения Маскарада')),
      body: BlocBuilder<MasqueradeBloc, MasqueradeState>(
        builder: (context, state) {
          if (state is ViolationsLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ViolationsLoaded) {
            return _buildViolationsList(context, state.violations);
          } else if (state is ViolationsError) {
            return Center(child: Text(state.message));
          }
          return const Center(child: Text('Нет данных о нарушениях'));
        },
      ),
    );
  }

  Widget _buildViolationsList(
    BuildContext context,
    List<ViolationModel> violations,
  ) {
    return ListView.builder(
      itemCount: violations.length,
      itemBuilder: (context, index) {
        final violation = violations[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text(violation.description),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Статус: ${_violationStatusText(violation.status)}'),
                Text('Потрачено голода: ${violation.hungerSpent}'),
                if (violation.violatorName != null)
                  Text('Нарушитель: ${violation.violatorName}'),
              ],
            ),
            trailing: violation.status == ViolationStatus.open
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {
                          // Проверка на null перед раскрытием
                          if (violation.id != null) {
                            context.read<MasqueradeBloc>().add(
                              RevealViolator(violationId: violation.id),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ошибка: у нарушения нет ID'),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: () {
                          // Проверка на null перед закрытием
                          if (violation.id != null) {
                            context.read<MasqueradeBloc>().add(
                              CloseViolation(violationId: violation.id),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Ошибка: у нарушения нет ID'),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  String _violationStatusText(ViolationStatus status) {
    switch (status) {
      case ViolationStatus.open:
        return 'Открыто';
      case ViolationStatus.closed:
        return 'Закрыто';
      case ViolationStatus.revealed:
        return 'Раскрыто';
    }
  }
}
