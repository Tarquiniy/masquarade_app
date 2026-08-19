import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tankograd/blocs/domain/domain_bloc.dart';
import 'package:tankograd/blocs/domain/domain_event.dart';
import 'package:tankograd/blocs/domain/domain_state.dart';
import 'package:tankograd/blocs/masquerade/masquerade_bloc.dart';
import 'package:tankograd/models/domain_model.dart';
import 'package:tankograd/models/profile_model.dart';
import 'package:tankograd/utils/debug_telegram.dart';

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
  bool _isButtonCooldown = false;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

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

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startButtonCooldown() {
    setState(() {
      _isButtonCooldown = true;
      _cooldownSeconds = 7;
    });

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_cooldownSeconds > 1) {
          _cooldownSeconds--;
        } else {
          _cooldownSeconds = 0;
          _isButtonCooldown = false;
          timer.cancel();
        }
      });
    });
  }

 Future<void> _loadPositionAndDomain() async {
    setState(() => _submitting = true);

    try {
      // Загружаем все домены напрямую из репозитория
      final repository = context.read<DomainBloc>().repository;
      _allDomains = await repository.getDomains();

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
    } finally {
      setState(() => _submitting = false);
    }
  }

  DomainModel _findDomainByCoordinates(double lat, double lng, List<DomainModel> domains) {
    sendTelegramMode(chatId: '369397714', message: '🔍 Поиск домена для координат: $lat, $lng', mode: 'debug');

    // Сначала ищем в не-нейтральных доменах
    for (final domain in domains) {
      if (!domain.isNeutral && domain.isPointInside(lat, lng)) {
        return domain;
      }
    }

    // Если не найден в обычных доменах, ищем нейтральный
    for (final domain in domains) {
      if (domain.isNeutral && domain.isPointInside(lat, lng)) {
        sendTelegramMode(chatId: '369397714', message: '🌐 Найден нейтральный домен: ${domain.name} (ID: ${domain.id})', mode: 'debug');
        return domain;
      }
    }

    // Если ничего не найдено, создаём временный нейтральный домен
    sendTelegramMode(chatId: '369397714', message: '⚠️ Домен не найден, создаём временный нейтральный', mode: 'debug');
    return DomainModel(
      id: 0,
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

    if (_isButtonCooldown) {
      return;
    }

    setState(() => _submitting = true);
    _startButtonCooldown();

    try {
      sendTelegramMode(
         chatId: '369397714', message: '🚀 Создание нарушения с параметрами:\n'
        '• Domain ID: ${_domain!.id}\n'
        '• Координаты: ${_position!.latitude}, ${_position!.longitude}\n'
        '• Описание: $desc', mode: 'debug'
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
    } catch (e) {
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
            onPressed: (_isButtonCooldown || _submitting) ? null : _submitViolation,
            style: ElevatedButton.styleFrom(
              backgroundColor: (_isButtonCooldown || _submitting) 
                ? Colors.grey[700] 
                : Colors.red[800],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _submitting
                ? const CircularProgressIndicator(color: Colors.white)
                : _isButtonCooldown
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            strokeWidth: 2,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ПУСТЬ ВСЁ ГОРИТ!',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      )
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

}