import 'package:flutter/material.dart';
import '../models/violation_model.dart';

class ViolationListTile extends StatelessWidget {
  final ViolationModel violation;

  const ViolationListTile({super.key, required this.violation});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    IconData icon;
    Color iconColor;

    switch (violation.status) {
      case ViolationStatus.open:
        bgColor = Colors.blue[900]!;
        icon = Icons.warning;
        iconColor = Colors.blue;
        break;
      case ViolationStatus.closed:
        bgColor = Colors.yellow[900]!;
        icon = Icons.check_circle;
        iconColor = Colors.yellow;
        break;
      case ViolationStatus.revealed:
        bgColor = Colors.green[900]!;
        icon = Icons.visibility;
        iconColor = Colors.green;
        break;
    }

    return Card(
      color: bgColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          violation.description,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          'Голода потрачено: ${violation.hungerSpent}',
          style: const TextStyle(color: Colors.white70),
        ),
        trailing: violation.status == ViolationStatus.open
            ? const Icon(Icons.arrow_forward, color: Colors.white)
            : null,
      ),
    );
  }
}
