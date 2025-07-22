import 'package:flutter/material.dart';

class PillarsEditor extends StatefulWidget {
  final List<Map<String, dynamic>> pillars;
  final Function(List<Map<String, dynamic>>) onChanged;

  const PillarsEditor({
    super.key,
    required this.pillars,
    required this.onChanged,
  });

  @override
  State<PillarsEditor> createState() => _PillarsEditorState();
}

class _PillarsEditorState extends State<PillarsEditor> {
  late List<Map<String, dynamic>> _pillars;

  @override
  void initState() {
    super.initState();
    _pillars = List<Map<String, dynamic>>.from(widget.pillars);
  }

  void _addPillar() {
    setState(() {
      _pillars.add({'name': 'Новый столп', 'destroyed': false});
      widget.onChanged(_pillars);
    });
  }

  void _updatePillar(int index, String name) {
    setState(() {
      _pillars[index]['name'] = name;
      widget.onChanged(_pillars);
    });
  }

  void _toggleDestroyed(int index) {
    setState(() {
      _pillars[index]['destroyed'] = !(_pillars[index]['destroyed'] ?? false);
      widget.onChanged(_pillars);
    });
  }

  void _removePillar(int index) {
    setState(() {
      _pillars.removeAt(index);
      widget.onChanged(_pillars);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Столпы',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._pillars.asMap().entries.map(
          (entry) {
            final index = entry.key;
            final pillar = entry.value;

            return ListTile(
              title: TextFormField(
                initialValue: pillar['name'] ?? '',
                decoration: const InputDecoration(labelText: 'Имя столпа'),
                onChanged: (v) => _updatePillar(index, v),
              ),
              leading: IconButton(
                icon: Icon(
                  pillar['destroyed'] == true
                      ? Icons.delete_forever
                      : Icons.shield,
                  color: pillar['destroyed'] == true
                      ? Colors.red
                      : Colors.green,
                ),
                onPressed: () => _toggleDestroyed(index),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _removePillar(index),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _addPillar,
          icon: const Icon(Icons.add),
          label: const Text('Добавить столп'),
        ),
      ],
    );
  }
}
