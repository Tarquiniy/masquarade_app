import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_event.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/masquerade/masquerade_bloc.dart';
import '../models/domain_model.dart';
import '../models/profile_model.dart';
import '../utils/debug_telegram.dart';

class MasqueradeViolationScreen extends StatefulWidget {
  final ProfileModel profile;

  const MasqueradeViolationScreen({super.key, required this.profile});

  @override
  State<MasqueradeViolationScreen> createState() =>
      _MasqueradeViolationScreenState();
}

class _MasqueradeViolationScreenState extends State<MasqueradeViolationScreen> {
  Position? _position;
  DomainModel? _domain;
  int _step = 0;
  int _hungerSpent = 1;
  final TextEditingController _descriptionController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadPositionAndDomain();

    try {
      final bloc = context.read<MasqueradeBloc>();
      print('✅ Bloc доступен: $bloc');
    } catch (e) {
      print('❌ Bloc недоступен: $e');
    }
  }

  Future<void> _loadPositionAndDomain() async {
    final domainBloc = context.read<DomainBloc>();

    if (domainBloc.state is! DomainsLoaded) {
      domainBloc.add(LoadDomains());
      await Future.delayed(const Duration(milliseconds: 300));
    }

    final pos = await Geolocator.getCurrentPosition();
    final domainState = context.read<DomainBloc>().state;

    DomainModel? foundDomain;

    if (domainState is DomainsLoaded) {
      for (final domain in domainState.domains) {
        if (domain.isPointInside(pos.latitude, pos.longitude)) {
          foundDomain = domain;
          break;
        }
      }

      foundDomain ??= domainState.domains.firstWhere(
        (d) => d.isNeutral,
        orElse: () => DomainModel(
          id: -1,
          name: 'Нейтральная зона',
          latitude: 0,
          longitude: 0,
          boundaryPoints: [],
          isNeutral: true,
          openViolationsCount: 0,
        ),
      );
    }

    setState(() {
      _position = pos;
      _domain = foundDomain;
    });
  }

  void _submitViolation() async {
    print('🔥 Кнопка "Пусть всё горит!" нажата');

    final desc = _descriptionController.text.trim();

    if (desc.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите описание')));
      return;
    }

    if (_position == null || _domain == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Геолокация не определена')));
      return;
    }

    setState(() => _submitting = true);

    try {
      context.read<MasqueradeBloc>().add(
        ReportViolation(
          description: desc,
          hungerSpent: _hungerSpent,
          latitude: _position!.latitude,
          longitude: _position!.longitude,
          domainId: _domain!.id,
        ),
      );

      await sendDebugToTelegram('🚀 ReportViolation отправлен из UI');
      Navigator.pop(context);
    } catch (e, stack) {
      await sendDebugToTelegram('❌ Ошибка UI: $e\n$stack');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка при отправке нарушения')),
      );
    } finally {
      setState(() => _submitting = false);
    }
  }

  Widget _buildStepContent() {
    if (_position == null || _domain == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_step == 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Сколько пунктов голода вы хотите потратить?',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          Slider(
            value: _hungerSpent.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: _hungerSpent.toString(),
            onChanged: (val) {
              setState(() => _hungerSpent = val.toInt());
            },
          ),
          Text(
            'Цена закрытия для владельца: ${_hungerSpent * 2} влияния',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Далее'),
          ),
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Опишите, что вы сделали, чтобы нарушить маскарад:',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Я выпил у полицейского прямо на площади...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey[900],
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitting ? null : _submitViolation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[800],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _submitting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'ПУСТЬ ВСЁ ГОРИТ!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Нарушение Маскарада')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildStepContent(),
      ),
    );
  }
}
