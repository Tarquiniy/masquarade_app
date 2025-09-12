import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:masquarade_app/blocs/domain/domain_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_event.dart';
import 'package:masquarade_app/blocs/domain/domain_state.dart';
import 'package:masquarade_app/blocs/masquerade/masquerade_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';

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
  List<DomainModel> _allDomains = [];

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
    setState(() => _submitting = true);

    try {
      // Загружаем все домены напрямую из репозитория
      final repository = context.read<DomainBloc>().repository;
      _allDomains = await repository.getDomains();
      sendDebugToTelegram('📦 Загружено ${_allDomains.length} доменов');

      // Получаем текущую позицию
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      // Определяем домен по координатам
      final domain = _findDomainByCoordinates(pos.latitude, pos.longitude, _allDomains);

      setState(() {
        _position = pos;
        _domain = domain;
      });

      sendDebugToTelegram(
        '📍 Позиция: ${pos.latitude}, ${pos.longitude}\n'
        '🏰 Определён домен: ${domain.name} (ID: ${domain.id})'
      );

    } catch (e) {
      sendDebugToTelegram('❌ Ошибка загрузки позиции и домена: $e');
    } finally {
      setState(() => _submitting = false);
    }
  }

  DomainModel _findDomainByCoordinates(double lat, double lng, List<DomainModel> domains) {
    sendDebugToTelegram('🔍 Поиск домена для координат: $lat, $lng');

    // Сначала ищем в не-нейтральных доменах
    for (final domain in domains) {
      if (!domain.isNeutral && domain.isPointInside(lat, lng)) {
        sendDebugToTelegram('✅ Найден не-нейтральный домен: ${domain.name} (ID: ${domain.id})');
        return domain;
      }
    }

    // Если не найден в обычных доменах, ищем нейтральный
    for (final domain in domains) {
      if (domain.isNeutral && domain.isPointInside(lat, lng)) {
        sendDebugToTelegram('🌐 Найден нейтральный домен: ${domain.name} (ID: ${domain.id})');
        return domain;
      }
    }

    // Если ничего не найдено, создаём временный нейтральный домен
    sendDebugToTelegram('⚠️ Домен не найден, создаём временный нейтральный');
    return DomainModel(
      id: 4,
      name: 'Нейтральная территория',
      latitude: lat,
      longitude: lng,
      boundaryPoints: [],
      isNeutral: true,
      openViolationsCount: 0,
      ownerId: '',
    );
  }

  void _submitViolation() async {
    final desc = _descriptionController.text.trim();

    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите описание')));
      return;
    }

    if (_position == null || _domain == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Геолокация не определена')));
      return;
    }

    setState(() => _submitting = true);

    try {
      sendDebugToTelegram(
        '🚀 Создание нарушения с параметрами:\n'
        '• Domain ID: ${_domain!.id}\n'
        '• Координаты: ${_position!.latitude}, ${_position!.longitude}\n'
        '• Описание: $desc'
      );

      context.read<MasqueradeBloc>().add(
        ReportViolation(
          description: desc,
          hungerSpent: _hungerSpent,
          latitude: _position!.latitude,
          longitude: _position!.longitude,
          domainId: _domain!.id,
        ),
      );

      sendDebugToTelegram('✅ ReportViolation отправлен с domainId: ${_domain!.id}');
    } catch (e, stack) {
      sendDebugToTelegram('❌ Ошибка при создании нарушения: $e\n$stack');
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
          Text(
            'Общее влияние домена: ${_domain!.influenceLevel}',
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
              hintText: 'Я отрастил когти прямо на площади...',
              hintStyle: TextStyle(color: Colors.grey[600]),
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
    return BlocListener<MasqueradeBloc, MasqueradeState>(
      listener: (context, state) {
        if (state is ViolationsError) {
          setState(() => _submitting = false);

          if (state.message == 'max_hunger_exceeded') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Невозможно создать нарушение: максимальный голод (5) будет превышен'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else if (state is ViolationReportedSuccessfully) {
          // Показываем красное всплывающее сообщение
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Нарушение успешно создано!',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
          // Закрываем экран после успешного создания
          Navigator.pop(context);
        }
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('Нарушение Маскарада')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _buildStepContent(),
      ),
    ));
  }

  DomainModel _findCorrectDomain(Position position, List<DomainModel> domains) {
  sendDebugToTelegram('🔍 Поиск домена для координат: ${position.latitude}, ${position.longitude}');

  // Сначала ищем в не-нейтральных доменах
  for (final domain in domains) {
    if (!domain.isNeutral && domain.isPointInside(position.latitude, position.longitude)) {
      sendDebugToTelegram('✅ Найден домен: ${domain.name} (ID: ${domain.id})');
      return domain;
    }
  }

  // Если не найден в обычных доменах, ищем нейтральный
  final neutralDomain = domains.firstWhere(
    (d) => d.isNeutral,
    orElse: () => DomainModel(
      id: 4, // fallback to neutral territory
      name: 'Нейтральная территория',
      latitude: 0,
      longitude: 0,
      boundaryPoints: [],
      isNeutral: true,
      openViolationsCount: 0,
      ownerId: '',
    ),
  );

  sendDebugToTelegram('🌐 Используется нейтральная территория: ${neutralDomain.name}');
  return neutralDomain;
}
}