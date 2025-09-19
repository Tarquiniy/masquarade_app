import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/blocs/domain/domain_event.dart';
import 'package:masquarade_app/blocs/domain/domain_state.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/screens/domains_screen.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../blocs/domain/domain_bloc.dart';
import '../blocs/masquerade/masquerade_bloc.dart';
import '../models/domain_model.dart';
import '../models/profile_model.dart';
import '../models/violation_model.dart';
import 'package:latlong2/latlong.dart' as latlng;

class DomainScreen extends StatefulWidget {
  final DomainModel domain;
  final ProfileModel profile;

  const DomainScreen({
    Key? key,
    required this.domain,
    required this.profile,
  }) : super(key: key);

  @override
  State<DomainScreen> createState() => _DomainScreenState();
}

class _DomainScreenState extends State<DomainScreen> {
  final MapController _mapController = MapController();
  Position? _position;
  bool _isLoadingLocation = false;
  bool _initialLoadNotDone = true;
  final int _maxSecurityLevel = 10;
  List<DomainModel> _allDomains = [];
  late DomainModel _currentDomain;
  StreamSubscription? _domainSubscription;
  final GlobalKey<_DomainScreenState> _domainScreenKey = GlobalKey();
  String? _ownerName;
  RealtimeChannel? _domainChannel;
  bool _hasShownNeutralDialog = false;
  StreamSubscription? _domainUpdateSubscription;
  bool _isCheckingLocation = false;

  @override
  void initState() {
    super.initState();
    _currentDomain = widget.domain;
    sendTelegramMode(chatId: '369397714', message: '🚀 Инициализация DomainScreen для домена ${_currentDomain.id}', mode: 'debug');

    // Подписка на обновления домена в реальном времени
    _subscribeToDomainUpdates();

    // Подписываемся на обновления DomainBloc
    _domainSubscription = context.read<DomainBloc>().stream.listen((state) {
      if (state is DomainsLoaded) {
        final updatedDomain = state.domains.firstWhere(
          (d) => d.id == _currentDomain.id,
          orElse: () => _currentDomain,
        );

        if (updatedDomain.securityLevel != _currentDomain.securityLevel) {
          setState(() {
            _currentDomain = updatedDomain;
          });
        }

        if (updatedDomain.isNeutral != _currentDomain.isNeutral) {
          setState(() {
            _currentDomain = updatedDomain;
          });

          // Если домен стал нейтральным, покажем сообщение
          if (updatedDomain.isNeutral) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Домен ${updatedDomain.name} стал нейтральным'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    });

    // Загружаем нарушения для текущего домена
    context.read<MasqueradeBloc>().add(LoadViolationsForDomain(_currentDomain.id));

    Future.delayed(Duration.zero, () {
      if (mounted) {
        _loadInitialData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_currentDomain.ownerId.isNotEmpty && _ownerName == null) {
      _loadOwnerName();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDomainData();
    });
  }

  @override
  void dispose() {
    _domainUpdateSubscription?.cancel();
    _domainChannel?.unsubscribe();
    _domainSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadOwnerName() async {
    final repository = context.read<DomainBloc>().repository;
    final ownerProfile = await repository.getProfileById(_currentDomain.ownerId);
    if (mounted) {
      setState(() {
        _ownerName = ownerProfile?.characterName;
      });
    }
  }

  void _subscribeToDomainUpdates() {
    final repository = context.read<DomainBloc>().repository;
    _domainUpdateSubscription = repository.client
        .from('domains')
        .stream(primaryKey: ['id'])
        .eq('id', _currentDomain.id)
        .listen((data) {
      if (data.isNotEmpty && mounted) {
        final updatedDomain = DomainModel.fromJson(data.first);
        setState(() {
          _currentDomain = updatedDomain;
        });
        sendTelegramMode(chatId: '369397714', message: '🔄 Домен обновлен в реальном времени: ${updatedDomain.isNeutral ? 'Нейтральный' : 'Не нейтральный'}', mode: 'debug');

        // Проверяем, нужно ли показать диалог после обновления
        _checkAndShowNeutralDialog();
      }
    });
  }

  void _checkAndShowNeutralDialog() async {
    if (_isCheckingLocation || _hasShownNeutralDialog) return;

    _isCheckingLocation = true;

    try {
      // Получаем актуальное местоположение
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _position = position;
      });

      // Получаем актуальные данные домена
      final repository = context.read<DomainBloc>().repository;
      final domains = await repository.getDomains();
      final currentDomain = domains.firstWhere(
        (d) => d.id == _currentDomain.id,
        orElse: () => _currentDomain,
      );

      setState(() {
        _currentDomain = currentDomain;
      });
      final message = '🔍 Проверка нейтрального домена:\n'
          '• isNeutral: ${_currentDomain.isNeutral}\n'
          '• Позиция: ${_position?.latitude}, ${_position?.longitude}\n'
          '• В границах: ${_currentDomain.isPointInside(_position!.latitude, _position!.longitude)}';
      sendTelegramMode(chatId: '369397714', message: message, mode: 'debug');

      // Проверяем все условия для показа диалога
      if (_currentDomain.isNeutral &&
          _position != null &&
          _currentDomain.isPointInside(_position!.latitude, _position!.longitude) &&
          !_hasShownNeutralDialog &&
          mounted) {

        _hasShownNeutralDialog = true;

        // Небольшая задержка для полной загрузки интерфейса
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _showNeutralDomainDialog(context);
          }
        });
      }
    } finally {
      _isCheckingLocation = false;
    }
  }

  Future<void> _refreshDomainData() async {
    final repository = context.read<DomainBloc>().repository;
    final domains = await repository.getDomains();
    final updatedDomain = domains.firstWhere(
      (d) => d.id == _currentDomain?.id,
      orElse: () => _currentDomain!,
    );

    if (mounted) {
      setState(() {
        _currentDomain = updatedDomain;
      });
    }
  }

  Future<void> _loadInitialData() async {
    await _getCurrentLocation();
    // Загружаем все домены для правильного определения
    final repository = context.read<DomainBloc>().repository;
    _allDomains = await repository.getDomains();

    // Обновляем текущий домен актуальными данными
    final updatedDomain = _allDomains.firstWhere(
      (d) => d.id == _currentDomain.id,
      orElse: () => _currentDomain,
    );

    setState(() {
      _currentDomain = updatedDomain;
    });
    final message='🏰 Детали домена:\n'
        '• ID: ${_currentDomain.id}\n'
        '• Название: ${_currentDomain.name}\n'
        '• Владелец: ${_currentDomain.ownerId}\n'
        '• Нейтральный: ${_currentDomain.isNeutral}\n'
        '• Открытых нарушений: ${_currentDomain.openViolationsCount}\n'
        '• Границы: ${_currentDomain.boundaryPoints.length} точек';
    sendTelegramMode(chatId: '369397714', message: message, mode: 'debug');

    // Проверяем и показываем диалог
    _checkAndShowNeutralDialog();
  }

  void _showNeutralDomainDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Захват территории',
            style: TextStyle(color: Color(0xFFd4af37), fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF2a0000),
          content: const Text(
            'Вы находитесь на территории нейтрального домена. Захватить домен?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showCaptureOptionsDialog(context);
              },
              child: const Text(
                'Да!',
                style: TextStyle(color: Color(0xFFd4af37)),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Нет, мне только покушать'),
                    backgroundColor: Colors.blue,
                  ),
                );
              },
              child: const Text(
                'Нет, мне только покушать',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  // Диалог выбора способа захвата
  void _showCaptureOptionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Способ захвата',
            style: TextStyle(color: Color(0xFFd4af37)),
          ),
          backgroundColor: const Color(0xFF2a0000),
          content: const Text(
            'Выберите способ захвата домена:',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processDomainCapture('силой');
              },
              child: const Text(
                'Захватить силой',
                style: TextStyle(color: Color(0xFF8b0000)),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processDomainCapture('купить');
              },
              child: const Text(
                'Купить',
                style: TextStyle(color: Color(0xFFd4af37)),
              ),
            ),
          ],
        );
      },
    );
  }

  // Обработка захвата домена
  void _processDomainCapture(String method) {
    // Показываем сообщение пользователю
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Снимите значок и ожидайте, с вами свяжутся'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 5),
      ),
    );

    // Отправляем супер-заметное уведомление мастерам
    final message =
        '‼️‼️‼️ ЗАПРОС НА ЗАХВАТ ДОМЕНА ‼️‼️‼️\n\n'
            '🚨 ВНИМАНИЕ МАСТЕРАМ! 🚨\n\n'
            'Игрок ${widget.profile.characterName} хочет захватить домен!\n'
            '• Домен: ${_currentDomain.name} (ID: ${_currentDomain.id})\n'
            '• Способ: $method\n'
            '• Игрок: ${widget.profile.characterName} (${widget.profile.clan}, ${widget.profile.sect})\n'
            '• Телеграм: @${widget.profile.external_name}\n'
            '• Координаты: ${_position?.latitude.toStringAsFixed(4)}, ${_position?.longitude.toStringAsFixed(4)}\n\n'
            '‼️ НЕМЕДЛЕННО СВЯЖИТЕСЬ С ИГРОКОМ ДЛЯ ПРОВЕДЕНИЯ СЦЕНКИ ЗАХВАТА! ‼️';

    sendTelegramMode(chatId: '369397714', message: message, mode: 'debug');

    // Дополнительно можно отправить уведомление в другой канал или сделать звонок API
    // для отправки SMS/email уведомлений мастерам
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final newPermission = await Geolocator.requestPermission();
        if (newPermission == LocationPermission.denied) {
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _position = pos;
        _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
      });
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentDomain == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ошибка', style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1a0000),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1a0000), Color(0xFF2a0000)],
            ),
          ),
          child: const Center(
            child: Text(
              'Домен не загружен',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ),
        ),
      );
    }

    return BlocListener<DomainBloc, DomainState>(
      listener: (context, state) {
        if (state is DomainsLoaded) {
          final updatedDomain = state.domains.firstWhere(
            (d) => d.id == _currentDomain!.id,
            orElse: () => _currentDomain!,
          );

          if (updatedDomain.securityLevel != _currentDomain!.securityLevel ||
              updatedDomain.influenceLevel != _currentDomain!.influenceLevel) {
            setState(() {
              _currentDomain = updatedDomain;
            });
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _currentDomain!.name.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFFd4af37),
              fontSize: 20,
              letterSpacing: 1.5,
              fontFamily: 'Gothic',
            ),
          ),
          backgroundColor: const Color(0xFF1a0000),
          iconTheme: const IconThemeData(color: Color(0xFFd4af37)),
          actions: [
            IconButton(
              icon: const Icon(Icons.my_location, size: 28),
              onPressed: _isLoadingLocation ? null : _getCurrentLocation,
              tooltip: 'Центрировать на моём местоположении',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFd4af37).withOpacity(0.5),
                    const Color(0xFF8b0000),
                    const Color(0xFFd4af37).withOpacity(0.5),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a0000), Color(0xFF2a0000)],
            stops: [0.3, 0.7],
          ),
        ),
        child: _buildBody(),
      ),
    ),
  );
}

  Widget _buildBody() {
    return Column(
      children: [
        // Карта
        Container(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                spreadRadius: 3,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
            child: _buildMap(),
          ),
        ),

        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                // Заголовок домена
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      _currentDomain!.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFd4af37),
                        letterSpacing: 2,
                        fontFamily: 'Gothic',
                        shadows: [
                          Shadow(
                            blurRadius: 10,
                            color: Color(0xFF8b0000),
                            offset: Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Статус домена
                if (_currentDomain!.isNeutral)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2a0000),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFd4af37), width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.warning, color: Color(0xFFd4af37), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Нейтральная территория',
                          style: TextStyle(
                            color: Color(0xFFd4af37),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Основная информация
                _buildSection(
                  title: 'ОСНОВНАЯ ИНФОРМАЦИЯ',
                  icon: Icons.info,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Статус', _currentDomain!.isNeutral ? 'Нейтральный' : 'Контролируемый'),
                      _buildInfoRow('Владелец', _currentDomain.ownerId.isNotEmpty ? _ownerName ?? _currentDomain.ownerId : 'Не назначен'),
                      _buildInfoRow('Доход', '${_currentDomain!.income} пунктов голода в день'),
                      _buildInfoRow('Координаты',
                          '${_currentDomain!.latitude.toStringAsFixed(4)}, '
                              '${_currentDomain!.longitude.toStringAsFixed(4)}'),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Статистика домена
                _buildSection(
                  title: 'СТАТИСТИКА ДОМЕНА',
                  icon: Icons.analytics,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildStatItem(
                            icon: Icons.security,
                            color: const Color(0xFF8b0000),
                            title: 'Защита',
                            value: '${_currentDomain!.securityLevel}/${_currentDomain!.maxSecurityLevel}',
                          ),
                          const SizedBox(width: 15),
                          _buildStatItem(
                            icon: Icons.attach_money_rounded,
                            color: const Color(0xFFd4af37),
                            title: 'Влияние',
                            value: '${_currentDomain!.influenceLevel}/${_currentDomain!.maxinfluenceLevel}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      // Доход по центру (убраны нарушения)
                      _buildCenteredStatItem(
                        //icon: Icons.attach_money,
                        color: const Color(0xFF006400),
                        title: 'Доход',
                        value: '${_currentDomain!.income}/день',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Управление защитой
                _buildProtectionManagementSection(),

                const SizedBox(height: 20),

                // Управление голодом
                _buildHungerManagementSection(),

                const SizedBox(height: 20),

                //Передача домена
                _buildDomainManagementSection(),

                const SizedBox(height: 20),

                // Активные нарушения
                _buildViolationsSection(),

              ],
            ),
          ),
        ),
      ],
    );
  }

  // Новый метод для создания центрированного элемента статистики
  Widget _buildCenteredStatItem({
    //required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Центрирование по горизонтали
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center, // Центрирование иконки и заголовка
            children: [
              //Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required IconData icon, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFFd4af37), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFd4af37),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a0000).withOpacity(0.8),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFd4af37).withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),


      ],
    );
  }

  Widget _buildDomainManagementSection() {
    final domain = _currentDomain;
    if (domain == null) return const SizedBox();

    return _buildSection(
      title: 'УПРАВЛЕНИЕ ДОМЕНОМ',
      icon: Icons.admin_panel_settings,
      child: Column(
        children: [
          // Информация о владении
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1a0000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFd4af37).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                const Text(
                  'Текущий владелец',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                    domain.ownerId.isNotEmpty ? _ownerName ?? domain.ownerId : 'Не назначен',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Кнопка передачи домена
          ElevatedButton.icon(
            onPressed: () => _showTransferDialog(context),
            icon: const Icon(Icons.swap_horiz, size: 24),
            label: const Text(
              'ПЕРЕДАТЬ ДОМЕН ДРУГОМУ ИГРОКУ',
              style: TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1a0000),
              foregroundColor: const Color(0xFFd4af37),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF8b0000), width: 2),
              ),
              elevation: 5,
              shadowColor: Colors.black.withOpacity(0.5),
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _showTransferDialog(BuildContext context) async {
    final players = await context.read<ProfileBloc>().getPlayers();

    // Фильтруем, исключая текущего владельца
    final availablePlayers = players.where((p) => p.id != _currentDomain!.ownerId).toList();

    if (availablePlayers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет других игроков для передачи домена'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Показываем диалог выбора игрока
    final selectedPlayer = await showDialog<ProfileModel>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a0000),
        title: const Text(
          'ПЕРЕДАТЬ ДОМЕН',
          style: TextStyle(color: Color(0xFFd4af37)),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availablePlayers.length,
            itemBuilder: (context, index) {
              final player = availablePlayers[index];
              return ListTile(
                title: Text(
                  player.characterName,
                  style: const TextStyle(color: Colors.white70),
                ),
                subtitle: Text(
                  '${player.clan}, ${player.sect}',
                  style: const TextStyle(color: Colors.grey),
                ),
                onTap: () => Navigator.pop(context, player),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );

    if (selectedPlayer != null) {
      // Подтверждаем передачу
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1a0000),
          title: const Text(
            'Подтверждение',
            style: TextStyle(color: Color(0xFFd4af37)),
          ),
          content: Text(
            'Вы уверены, что хотите передать домен "${_currentDomain!.name}" игроку ${selectedPlayer.characterName}?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить', style: TextStyle(color: Color(0xFFd4af37))),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        _performDomainTransfer(context, selectedPlayer);
      }
    }
  }

  void _performDomainTransfer(BuildContext context, ProfileModel recipient) async {
    final domain = _currentDomain;
    if (domain == null) return;

    try {
      // Выполняем передачу домена
      final repository = context.read<DomainBloc>().repository;
      final domainBloc = context.read<DomainBloc>();
      final profileBloc = context.read<ProfileBloc>();

      await repository.transferDomain(domain.id.toString(), recipient.id);

      // Обновляем DomainBloc - загружаем свежие данные
      domainBloc.add(LoadDomains());

      // Обновляем ProfileBloc для текущего пользователя
      final currentProfileState = profileBloc.state;
      if (currentProfileState is ProfileLoaded) {
        final currentProfile = currentProfileState.profile;
        final freshProfile = await repository.getProfileById(currentProfile.id);
        if (freshProfile != null) {
          profileBloc.add(SetProfile(freshProfile));
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Домен "${domain.name}" передан ${recipient.characterName}'),
          backgroundColor: Colors.green[800],
        ),
      );

      // Возвращаемся на предыдущий экран
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка передачи домена: ${e.toString()}'),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  Widget _buildHungerManagementSection() {
    final domain = _currentDomain;
    if (domain == null) return const SizedBox();

    return _buildSection(
      title: 'УПРАВЛЕНИЕ ГОЛОДОМ',
      icon: Icons.restaurant,
      child: Column(
        children: [
          // Индикатор доступного голода из baseIncome
          _buildStatIndicator(
            'Доступный голод домена',
            '${domain.baseIncome} пунктов',
            domain.baseIncome / 10,
            const Color(0xFF8b0000),
            Icons.attach_money,
          ),

          const SizedBox(height: 20),

          // Кнопка "Накормить"
          ElevatedButton.icon(
            onPressed: () => _showFeedDialog(context),
            icon: const Icon(Icons.restaurant, size: 24),
            label: const Text(
              'НАКОРМИТЬ',
              style: TextStyle(fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1a0000),
              foregroundColor: const Color(0xFFd4af37),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF8b0000), width: 2),
              ),
              elevation: 5,
              shadowColor: Colors.black.withOpacity(0.5),
            ),
          ),

          const SizedBox(height: 15),

          // Информация
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1a0000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFd4af37).withOpacity(0.3)),
            ),
            child: const Text(
              'Использовать доступный голод домена для кормления других игроков.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFd4af37),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  void _showFeedDialog(BuildContext context) async {
    // Получаем список всех игроков
    final players = await context.read<ProfileBloc>().getPlayers();

    // Сортируем по имени персонажа
    players.sort((a, b) => a.characterName.compareTo(b.characterName));

    // Выбранный игрок (изначально null)
    ProfileModel? selectedPlayer;

    // Контроллер для поиска
    final searchController = TextEditingController();

    // Показываем диалог выбора игрока
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Фильтруем игроков по поисковому запросу
          final filteredPlayers = searchController.text.isEmpty
              ? players
              : players.where((player) =>
                  player.characterName.toLowerCase().contains(
                    searchController.text.toLowerCase()
                  )).toList();

          return AlertDialog(
            title: const Text('Выберите игрока'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Поле поиска
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: 'Поиск по имени...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Список игроков
                  SizedBox(
                    height: 300,
                    width: double.maxFinite,
                    child: ListView.builder(
                      itemCount: filteredPlayers.length,
                      itemBuilder: (context, index) {
                        final player = filteredPlayers[index];
                        return ListTile(
                          leading: const Icon(Icons.person),
                          title: Text(player.characterName),
                          selected: selectedPlayer?.id == player.id,
                          onTap: () {
                            setState(() {
                              selectedPlayer = player;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: selectedPlayer != null
                    ? () {
                        Navigator.pop(context);
                        _showAmountDialog(context, selectedPlayer!);
                      }
                    : null,
                child: const Text('Далее'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAmountDialog(BuildContext context, ProfileModel targetPlayer) async {
    final domain = _currentDomain;
    if (domain == null) return;

    int amount = 1;
    int maxAllowed = targetPlayer.hunger;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Накормить ${targetPlayer.characterName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Сколько пунктов голода передать?'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        if (amount > 1) {
                          setState(() => amount--);
                        }
                      },
                    ),
                    Text(
                      '$amount',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        if (amount < domain.baseIncome) {
                          setState(() => amount++);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Максимум: ${domain.baseIncome} (доступно в домене)',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Загружаем свежие данные получателя для окончательной проверки
                  final freshTarget = await context.read<DomainBloc>().repository.getProfileById(targetPlayer.id);

                  if (freshTarget == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('❌ Ошибка: игрок не найден'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  // Обновляем maxAllowed на основе свежих данных
                  final currentMaxAllowed = freshTarget.hunger;

                  if (amount > currentMaxAllowed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Нельзя передать столько крови, '
                          'выберите меньше',
                        ),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  } else {
                    Navigator.pop(context);
                    _transferHunger(context, targetPlayer, amount);
                  }
                },
                child: const Text('Подтвердить'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _transferHunger(BuildContext context, ProfileModel targetPlayer, int amount) async {
    try {
      final repository = context.read<DomainBloc>().repository;
      final domainBloc = context.read<DomainBloc>();
      final profileBloc = context.read<ProfileBloc>();
      final domain = _currentDomain;

      // Загружаем свежие данные получателя
      final freshTarget = await repository.getProfileById(targetPlayer.id);
      if (freshTarget == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка: игрок не найден'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (domain.baseIncome < amount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Недостаточно доступного голода в домене'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final result = await repository.transferHungerFromDomain(
        domain.id,
        targetPlayer.id,
        amount
      );

      if (result != null && result['success'] == true) {
        final newBaseIncome = domain.baseIncome - amount;
        setState(() {
          _currentDomain = _currentDomain!.copyWith(baseIncome: newBaseIncome);
        });

        domainBloc.add(UpdateDomainBaseIncome(domain.id, newBaseIncome));

        final newHunger = freshTarget.hunger + amount;

        // Обновляем состояние получателя
        if (targetPlayer.id == widget.profile.id) {
          profileBloc.add(UpdateHunger(newHunger));

          // Принудительно обновляем главный экран
          context.read<ProfileBloc>().add(UpdateProfile(
            widget.profile.copyWith(hunger: newHunger)
          ));
        } else {
          await repository.updateHunger(targetPlayer.id, newHunger);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$amount пунктов голода переданы ${freshTarget.characterName}'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка передачи голода'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка передачи голода: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProtectionManagementSection() {
    final domain = _currentDomain;
    if (domain == null) return const SizedBox();

    final currentProtection = domain.securityLevel;
    final maxProtection = domain.maxSecurityLevel;
    final currentInfluence = domain.influenceLevel;
    final maxInfluence = domain.maxinfluenceLevel;
    final bool isMaxProtectionReached = maxProtection >= 10;

    return _buildSection(
      title: 'УПРАВЛЕНИЕ ЗАЩИТОЙ',
      icon: Icons.shield,
      child: Column(
        children: [
          // Индикаторы защиты и влияния
          Row(
            children: [
              Expanded(
                child: _buildStatIndicator(
                  'Защита',
                  '$currentProtection/$maxProtection',
                  currentProtection / maxProtection,
                  const Color(0xFF8b0000),
                  Icons.security,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildStatIndicator(
                  'Влияние',
                  '$currentInfluence/$maxInfluence',
                  currentInfluence / maxInfluence,
                  const Color(0xFFd4af37),
                  Icons.auto_awesome,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Кнопки управления
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _restoreProtection(context),
                  icon: const Icon(Icons.shield, size: 20),
                  label: const Text('Восстановить'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a0000),
                    foregroundColor: const Color(0xFFd4af37),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFd4af37), width: 1),
                    ),
                    elevation: 5,
                    shadowColor: Colors.black.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: isMaxProtectionReached 
                  ? null  // Отключаем кнопку при достижении максимума
                  : () => _upgradeProtection(context),
                icon: const Icon(Icons.enhanced_encryption, size: 20),
                label: Text(isMaxProtectionReached ? 'Максимум' : 'Повысить'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isMaxProtectionReached 
                    ? Colors.grey[700]  // Серый цвет для неактивной кнопки
                    : const Color(0xFF1a0000),
                  foregroundColor: const Color(0xFFd4af37),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: isMaxProtectionReached 
                        ? Colors.grey[600]!  // Серый бордер для неактивной кнопки
                        : const Color(0xFFd4af37), 
                      width: 1
                    ),
                  ),
                  elevation: isMaxProtectionReached ? 0 : 5,  // Убираем тень у неактивной кнопки
                  shadowColor: Colors.black.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 15),

        // Информация о стоимости
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1a0000),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFd4af37).withOpacity(0.3)),
          ),
          child: Text(
            isMaxProtectionReached
              ? 'Восстановление: 2 влияния → 1 защита\nДостигнут максимальный уровень защиты (10)'
              : 'Восстановление: 2 влияния → 1 защита\nПовышение: 4 влияния → +1 к максимуму',
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFFd4af37),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

  Widget _buildStatIndicator(String title, String value, double progress, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a0000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFd4af37).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[800],
            color: color,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFd4af37),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ));
  }

  void _restoreProtection(BuildContext context) async {
    final domain = _currentDomain;
    if (domain == null) return;

    int amount = 1;
    final int availableInfluence = domain.influenceLevel;
    final int currentProtection = domain.securityLevel;
    final int maxProtection = domain.maxSecurityLevel;
    final int maxRestorable = (availableInfluence / 2).floor();
    final int maxFromProtection = maxProtection - currentProtection;
    final int maxAmount = maxRestorable > maxFromProtection ? maxFromProtection : maxRestorable;

    if (maxAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Недостаточно влияния для восстановления защиты или защита уже максимальна'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Показываем диалог
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        int tempAmount = amount;
        return StatefulBuilder(
          builder: (context, setState) {
            return SimpleDialog(
              title: const Text('Восстановление защиты'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('Доступно влияния: $availableInfluence/${domain.maxinfluenceLevel}'),
                      const SizedBox(height: 10),
                      Text('Текущая защита: $currentProtection/$maxProtection'),
                      const SizedBox(height: 10),
                      const Text('Выберите количество для восстановления:'),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove),
                            onPressed: () {
                              if (tempAmount > 1) {
                                setState(() => tempAmount--);
                              }
                            },
                          ),
                          Text('$tempAmount', style: TextStyle(fontSize: 20)),
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              if (tempAmount < maxAmount) {
                                setState(() => tempAmount++);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text('Стоимость: ${tempAmount * 2} влияния'),
                      Text('Будет восстановлено: $tempAmount ед. защиты'),
                    ],
                  ),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, tempAmount),
                  child: const Text('Восстановить'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Отмена'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    amount = result;
    final cost = amount * 2;
    final newInfluence = availableInfluence - cost;
    final newSecurity = currentProtection + amount;

    try {
      final repository = context.read<DomainBloc>().repository;

      // Обновляем влияние
      await repository.updateDomainInfluenceLevel(domain.id, newInfluence);

      // Обновляем защиту
      await repository.updateDomainSecurity(domain.id, newSecurity);

      // Обновляем локальное состояние
      setState(() {
        _currentDomain = domain.copyWith(
          securityLevel: newSecurity,
          influenceLevel: newInfluence,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Защита восстановлена на $amount ед. (потрачено $cost влияния)'),
          backgroundColor: Colors.green,
        ),
      );

      context.read<DomainBloc>().add(LoadDomains());

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
    await _refreshDomainData();
  }

  Future<void> _upgradeProtection(BuildContext context) async {
  final domain = _currentDomain;
  if (domain == null) return;

  // Проверяем, не достигнут ли уже максимальный уровень защиты (10)
  if (domain.maxSecurityLevel >= 10) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Максимальный уровень защиты уже достигнут (10)')),
    );
    return;
  }

  final availableInfluence = domain.influenceLevel;

  if (availableInfluence < 4) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Недостаточно влияния')),
    );
    return;
  }

  try {
    final repository = context.read<DomainBloc>().repository;
    final newInfluence = availableInfluence - 4;
    final newMaxSecurity = domain.maxSecurityLevel + 1;

    // Обновляем данные
    await repository.updateDomainInfluenceLevel(domain.id, newInfluence);
    await repository.updateDomainMaxSecurity(domain.id, newMaxSecurity);

    // Обновляем локальное состояние
    setState(() {
      _currentDomain = domain.copyWith(
        influenceLevel: newInfluence,
        maxSecurityLevel: newMaxSecurity,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Защита повышена')),
    );

    // Обновляем данные
    await _refreshDomainData();

  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ошибка: ${e.toString()}')),
    );
  }
}

  Future<void> _updateDomainSecurityAndInfluence(int domainId, int newSecurity, int newInfluence) async {
    final repository = context.read<DomainBloc>().repository;

    // Обновляем безопасность
    await repository.updateDomainSecurity(domainId, newSecurity);

    // Обновляем влияние
    await repository.updateDomainInfluenceLevel(domainId, newInfluence);
  }

  Widget _buildMap() {
    return BlocBuilder<MasqueradeBloc, MasqueradeState>(
      builder: (context, state) {
        List<ViolationModel> violations = [];
        if (state is ViolationsLoaded) {
          violations = state.violations.where((v) => v.status != ViolationStatus.closed).toList();
        }

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _currentDomain.boundaryPoints.isNotEmpty
                ? _currentDomain.boundaryPoints[0]
                : const latlng.LatLng(55.751244, 37.618423),
            initialZoom: 13,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            ),
            if (_currentDomain.boundaryPoints.isNotEmpty)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _currentDomain.boundaryPoints,
                    color: Colors.blue.withOpacity(0.25),
                    borderColor: Colors.blue,
                    borderStrokeWidth: 3,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (_position != null)
                  Marker(
                    point: latlng.LatLng(_position!.latitude, _position!.longitude),
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.person_pin_circle,
                      color: Colors.deepPurple,
                      size: 40,
                    ),
                  ),
                Marker(
                  point: latlng.LatLng(_currentDomain.latitude, _currentDomain.longitude),
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_city,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
                // Маркеры для нарушений
                ...violations.map((violation) => Marker(
                  point: latlng.LatLng(violation.latitude, violation.longitude),
                  width: 30,
                  height: 30,
                  child: Icon(
                    _getViolationIcon(violation.status),
                    color: _getViolationColor(violation.status),
                    size: 30,
                  ),
                )).toList(),
              ],
            ),
          ],
        );
      },
    );
  }

  IconData _getViolationIcon(ViolationStatus status) {
    switch (status) {
      case ViolationStatus.open:
        return Icons.warning;
      case ViolationStatus.closed:
        return Icons.check_circle;
      case ViolationStatus.revealed:
        return Icons.visibility;
    }
  }

  Color _getViolationColor(ViolationStatus status) {
    switch (status) {
      case ViolationStatus.open:
        return Colors.yellow;
      case ViolationStatus.closed:
        return Colors.green;
      case ViolationStatus.revealed:
        return Colors.purple;
    }
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViolationCard(ViolationModel violation) {
    // Определяем состояние нарушения на основе closedAt и revealedAt
    final bool isClosed = violation.closedAt != null;
    final bool isRevealed = violation.revealedAt != null;
    final bool isClosedAndRevealed = isClosed && isRevealed;

    // Проверяем, прошло ли менее 3 часов с момента создания
    final hoursSinceCreation = DateTime.now().difference(violation.createdAt).inHours;
    final bool withinThreeHours = hoursSinceCreation < 3;

    // Определяем, какие кнопки показывать на основе состояния
    final bool showCloseButton = !isClosed;
    final bool showRevealButton = !isRevealed && withinThreeHours && !isClosedAndRevealed;

    // Определяем цвет и иконку на основе состояния
    Color borderColor;
    Color backgroundColor;
    Color textColor;
    IconData icon;

    if (isClosedAndRevealed) {
      // Четвертое состояние: закрыто и раскрыто - зеленый, кнопок нет
      borderColor = Colors.green;
      backgroundColor = Colors.green.withOpacity(0.1);
      textColor = Colors.green;
      icon = Icons.check_circle;
    } else if (isClosed) {
      // Второе состояние: закрыто, но не раскрыто - зеленый
      borderColor = Colors.green;
      backgroundColor = Colors.green.withOpacity(0.1);
      textColor = Colors.green;
      icon = Icons.check_circle;
    } else if (isRevealed) {
      // Третье состояние: раскрыто, но не закрыто - фиолетовый
      borderColor = Colors.purple;
      backgroundColor = Colors.purple.withOpacity(0.1);
      textColor = Colors.purple;
      icon = Icons.visibility;
    } else {
      // Первое состояние: не закрыто и не раскрыто - желтый
      borderColor = Colors.yellow;
      backgroundColor = Colors.yellow.withOpacity(0.1);
      textColor = Colors.yellow;
      icon = Icons.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        leading: Icon(
          icon,
          color: borderColor,
        ),
        title: Text(
          violation.description,
          style: TextStyle(
            color: textColor,
            fontWeight: isClosed ? FontWeight.normal : FontWeight.bold,
            decoration: isClosed ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Создано: ${_formatDateTime(violation.createdAt)}',
              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 12),
            ),
            if (violation.violatorName != null)
              Text(
                'Нарушитель: ${violation.violatorName}',
                style: TextStyle(color: textColor, fontSize: 12),
              ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_drop_down,
          color: borderColor.withOpacity(0.7),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Информация о нарушении
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildViolationStat('Голод', violation.hungerSpent.toString(), Icons.local_dining, textColor),
                    _buildViolationStat('Закрытие', '${violation.costToClose}', Icons.security, textColor),
                    _buildViolationStat('Раскрытие', '${violation.costToReveal}', Icons.visibility, textColor),
              ]),
                const SizedBox(height: 16),

                // Кнопки действий - не показываем, если нарушение закрыто и раскрыто
                if (!isClosedAndRevealed && (showCloseButton || showRevealButton))
                  Row(
                    children: [
                      if (showCloseButton)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _closeViolation(context, violation),
                            icon: Icon(Icons.check_circle, size: 18, color: Colors.white),
                            label: const Text('Восстановить Маскарад', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      if (showCloseButton && showRevealButton)
                        const SizedBox(width: 10),
                      if (showRevealButton)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _revealViolator(context, violation),
                            icon: Icon(Icons.visibility, size: 18, color: Colors.white),
                            label: const Text('Узнать нарушителя', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),

                // Информация о стоимости
                if (!isClosedAndRevealed && (showCloseButton || showRevealButton))
                  const SizedBox(height: 12),
                if (showCloseButton)
                  Text(
                    'Стоимость закрытия: ${violation.costToClose} влияния',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (showRevealButton)
                  Text(
                    'Стоимость раскрытия нарушителя: ${violation.costToReveal} влияния',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (!withinThreeHours && !isRevealed)
                  Text(
                    'Узнать имя нарушителя невозможно, время истекло',
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViolationStat(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
        Text(value, style: TextStyle(fontSize: 14, color: color)),
      ],
    );
  }

  void _closeViolation(BuildContext context, ViolationModel violation) async {
    final domain = _currentDomain;
    if (domain == null) return;

    // Проверяем достаточно ли влияния у домена
    if (domain.influenceLevel < violation.costToClose) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Влияния не достаточно для закрытия этого нарушения'),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      // Закрываем нарушение
      final repository = context.read<MasqueradeBloc>().repository;
      await repository.closeViolation(violation.id, domain.ownerId);

      // Обновляем влияние домена
      final newInfluence = domain.influenceLevel - violation.costToClose;
      await repository.updateDomainInfluenceLevel(domain.id, newInfluence);

      // Обновляем состояние
      context.read<DomainBloc>().add(UpdateDomainInfluence(domain.id, newInfluence));

      // Обновляем список нарушений
      context.read<MasqueradeBloc>().add(LoadViolationsForDomain(domain.id));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Вы закрыли нарушение Маскарада'),
          backgroundColor: Colors.green[800],
          duration: const Duration(seconds: 3),
        ),
      );

      // Обновляем данные
      await _refreshDomainData();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  void _revealViolator(BuildContext context, ViolationModel violation) async {
    final domain = _currentDomain;
    if (domain == null) return;

    // Проверяем достаточно ли влияния у ДОМЕНА
    if (domain.influenceLevel < violation.costToReveal) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Влияния домена недостаточно, чтобы узнать, кто это был'),
          backgroundColor: Colors.red[800],
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      // Раскрываем нарушителя
      final repository = context.read<MasqueradeBloc>().repository;

      // Получаем профиль нарушителя
      final violatorProfile = await repository.getProfileById(violation.violatorId);
      if (violatorProfile == null) {
        throw Exception('Профиль нарушителя не найден');
      }

      // Обновляем влияние ДОМЕНА
      final newInfluence = domain.influenceLevel - violation.costToReveal;
      await repository.updateDomainInfluenceLevel(domain.id, newInfluence);

      // Раскрываем нарушителя
      await repository.revealViolation(
        id: violation.id,
        violatorName: violatorProfile.characterName,
        revealedAt: DateTime.now().toIso8601String(),
      );

      // Обновляем состояние домена
      context.read<DomainBloc>().add(UpdateDomainInfluence(domain.id, newInfluence));

      // Обновляем список нарушений
      context.read<MasqueradeBloc>().add(LoadViolationsForDomain(domain.id));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Это нарушение маскарада совершил ${violatorProfile.characterName}'),
          backgroundColor: Colors.green[800],
          duration: const Duration(seconds: 5),
        ),
      );

      // Обновляем данные
      await _refreshDomainData();

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  Widget _buildViolationsSection() {
    return _buildSection(
      title: 'АКТИВНЫЕ НАРУШЕНИЯ МАСКАРАДА',
      icon: Icons.warning_amber,
      child: BlocBuilder<MasqueradeBloc, MasqueradeState>(
        builder: (context, state) {
          if (state is ViolationsLoading) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFd4af37)),
              ),
            );
          }

          if (state is ViolationsLoaded) {
            final violations = state.violations
                .where((v) => v.domainId == _currentDomain!.id)
                .toList();

            if (violations.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1a0000),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFd4af37).withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.verified_user, size: 60, color: const Color(0xFFd4af37).withOpacity(0.7)),
                    const SizedBox(height: 15),
                    const Text(
                      'Нарушений не обнаружено',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'На территории вашего домена всё спокойно',
                      style: TextStyle(color: Colors.grey[400]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: violations.map((v) => _buildViolationCard(v)).toList(),
            );
          }

          return const SizedBox();
        },
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

}