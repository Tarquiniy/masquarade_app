// home_screen.dart — web/PWA-ready версия с HTML-оверлеем для просмотра Google Docs

import 'dart:async';
import 'dart:math';
import 'dart:html' as html; // web-only (PWA)
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:masquarade_app/blocs/auth/auth_bloc.dart';
import 'package:masquarade_app/blocs/domain/domain_event.dart';
import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/screens/domains_screen.dart';
import 'package:masquarade_app/screens/enter_username_screen.dart';
import 'package:masquarade_app/utils/clan_utils.dart';

import '../blocs/domain/domain_bloc.dart';
import '../blocs/domain/domain_state.dart';
import '../blocs/masquerade/masquerade_bloc.dart';
import 'profile_screen.dart';
import 'masquerade_violation_screen.dart';
import 'domain_screen.dart';
import '../utils/debug_telegram.dart';
import 'carpet_chat_screen.dart';
import '../utils/orientation_plugin.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart'; // используется в мобильной (не-web) версии

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = state.profile;

        return BlocListener<AuthBloc, AuthState>(
          listener: (context, authState) {
            if (authState is AuthInitial) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const EnterUsernameScreen()),
                (route) => false,
              );
            }
          },
          child: _HomeScreenContent(profile: state.profile),
        );
      },
    );
  }
}

class _HomeScreenContent extends StatefulWidget {
  final ProfileModel profile;

  const _HomeScreenContent({required this.profile});

  @override
  State<_HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<_HomeScreenContent> with TickerProviderStateMixin {
  Position? _position;
  final MapController _mapController = MapController();
  bool _isLoadingLocation = false;
  List<DomainModel>? _domains;
  bool _isLoading = true;
  String? _error;
  late ProfileModel _currentProfile;
  double? _compassHeading; // degrees
  StreamSubscription? _compassSubscription;
  double _deviceOrientation = 0; // radians (from OrientationPlugin)
  StreamSubscription? _orientationSubscription;
  DateTime? _lastHuntPressed;
  DateTime? _lastViolatePressed;
  DateTime? _lastDomainPressed;
  Timer? _cooldownTimer;

  DomainModel? _currentDomain;
  bool _neutralizationHandled = false;

  // Храним текущий поворот карты в градусах (положительный = ? зависит от версии flutter_map)
  double _mapRotationDegrees = 0.0;

  // URL документа (твой Google Doc) — используем /preview для встраивания
  static const String _docUrlBase = 'https://docs.google.com/document/d/1dgdbmC_T6EU-ORN0k5ik8ArtYBrEWzmM52LAghyenx8';
  String get _docPreviewUrl => '$_docUrlBase/preview';
  String get _docEditUrl => '$_docUrlBase/edit?usp=sharing';

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    _loadAllData();

    // Подписка на компас для мобильных устройств
    _compassSubscription = FlutterCompass.events?.listen((event) {
      setState(() {
        _compassHeading = event.heading;
      });
    });

    // Подписка на ориентацию для веб-приложения
    _orientationSubscription =
        OrientationPlugin.orientationEvents?.listen((event) {
      setState(() {
        _deviceOrientation = event.yaw * pi / 180; // Конвертируем градусы в радианы
      });
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _orientationSubscription?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      _position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final repository = context.read<DomainBloc>().repository;
      _domains = await repository.getDomains();

      final freshProfile = await repository.getProfileById(_currentProfile.id);
      if (freshProfile != null) {
        _currentProfile = freshProfile;
        context.read<ProfileBloc>().add(SetProfile(freshProfile));
      }

      setState(() {
        _isLoading = false;
      });

      _checkNeutralDomain();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  bool _isHuntCooldown() {
    return _lastHuntPressed != null &&
        DateTime.now().difference(_lastHuntPressed!).inSeconds < 5;
  }

  bool _isViolateCooldown() {
    return _lastViolatePressed != null &&
        DateTime.now().difference(_lastViolatePressed!).inSeconds < 5;
  }

  bool _isDomainCooldown() {
    return _lastDomainPressed != null &&
        DateTime.now().difference(_lastDomainPressed!).inSeconds < 5;
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isHuntCooldown() && !_isViolateCooldown() && !_isDomainCooldown()) {
        timer.cancel();
      }
      setState(() {}); // Обновляем состояние для перерисовки кнопок
    });
  }

  void _onHuntWithCooldown() {
    if (_isHuntCooldown()) return;

    setState(() {
      _lastHuntPressed = DateTime.now();
    });
    _startCooldownTimer();
    _onHunt();
  }

  void _onViolateWithCooldown() {
    if (_isViolateCooldown()) return;

    setState(() {
      _lastViolatePressed = DateTime.now();
    });
    _startCooldownTimer();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<MasqueradeBloc>(),
          child: MasqueradeViolationScreen(profile: widget.profile),
        ),
      ),
    );
  }

  void _onDomainWithCooldown() {
    if (_isDomainCooldown()) return;

    setState(() {
      _lastDomainPressed = DateTime.now();
    });
    _startCooldownTimer();
    _openDomainScreen(); // Вызываем оригинальный метод
  }

  void _checkNeutralDomain() {
    if (_position == null || _domains == null) return;
    final neutralDomain = _domains!.firstWhere(
      (d) => d.isNeutral && d.isPointInside(_position!.latitude, _position!.longitude),
      orElse: () => DomainModel(
        id: -1,
        name: 'null',
        ownerId: '',
        latitude: 0,
        longitude: 0,
        boundaryPoints: [],
        isNeutral: false,
      ),
    );

    if (neutralDomain.id != -1) {
      _currentDomain = neutralDomain;
      _showNeutralDomainDialog();
    }
  }

  void _showNeutralDomainDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Нейтральный домен"),
        content: const Text("Вы находитесь на территории нейтрального домена. Захватить домен?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Нет, мне только покушать"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showCaptureOptions();
            },
            child: const Text("Да!"),
          ),
        ],
      ),
    );
  }

  void _showCaptureOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Выберите способ захвата"),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _finalizeCapture("Захватить силой");
            },
            child: const Text("Захватить силой"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _finalizeCapture("Купить");
            },
            child: const Text("Купить"),
          ),
        ],
      ),
    );
  }

  void _finalizeCapture(String method) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Захват инициирован"),
        content: const Text("Снимите значок и ожидайте, с вами свяжутся"),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );

    if (_currentDomain != null) {
      final message =
      '‼️‼️‼️ ЗАПРОС НА ЗАХВАТ ДОМЕНА ‼️‼️‼️\n\n'
      '🚨 ВНИМАНИЕ МАСТЕРАМ! 🚨\n\n'
      'Игрок ${widget.profile.characterName} хочет захватить домен!\n'
      '• Домен: ${_currentDomain!.name} (ID: ${_currentDomain!.id})\n'
      '• Способ: $method\n'
      '• Игрок: ${widget.profile.characterName} (${widget.profile.clan}, ${widget.profile.sect})\n'
      '• Телеграм: @${widget.profile.external_name}\n'
      '• Координаты: ${_position?.latitude.toStringAsFixed(4)}, ${_position?.longitude.toStringAsFixed(4)}\n\n'
      '‼️ НЕМЕДЛЕННО СВЯЖИТЕСЬ С ИГРОКОМ ДЛЯ ПРОВЕДЕНИЯ СЦЕНКИ ЗАХВАТА! ‼️';

      sendTelegramMode(chatId: '369397714', message: message, mode: 'debug');
    }
  }

  Future<void> _initLocation() async {
    setState(() => _isLoadingLocation = true);

    // Всегда запрашиваем свежую геолокацию
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await Geolocator.requestPermission();
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

  void _onHunt() {
    if (_isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные еще загружаются')),
      );
      return;
    }

    if (_error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $_error')),
      );
      return;
    }

    if (_currentProfile.hunger <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ваш голод утолён, охотиться незачем'),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    if (_position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Геолокация не определена'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_domains == null || _domains!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Домены не загружены'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final currentDomain = _findDomainAtPosition(_domains!);
    if (currentDomain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Вы находитесь вне территории игры'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final isOwner = currentDomain.ownerId == _currentProfile.id ||
        _currentProfile.domainIds.contains(currentDomain.id);

    context.read<MasqueradeBloc>().add(
      StartHunt(
        isDomainOwner: isOwner,
        domainId: currentDomain.id,
        position: _position!,
      ),
    );
  }

  DomainModel? _findDomainAtPosition(List<DomainModel> domains) {
    if (_position == null) return null;
    // Сначала ищем в не-нейтральных доменах
    for (final domain in domains) {
      if (!domain.isNeutral && domain.isPointInside(_position!.latitude, _position!.longitude)) {
        return domain;
      }
    }

    // Если не найден в обычных доменах, ищем нейтральный
    for (final domain in domains) {
      if (domain.isNeutral && domain.isPointInside(_position!.latitude, _position!.longitude)) {
        return domain;
      }
    }

    // Если ничего не найдено, возвращаем нейтральную территорию
    return DomainModel(
      id: 0,
      name: 'Нейтральная зона',
      latitude: _position!.latitude,
      longitude: _position!.longitude,
      boundaryPoints: [],
      isNeutral: true,
      openViolationsCount: 0,
      ownerId: 'нет',
    );
  }

  void _openProfileScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(profile: _currentProfile),
      ),
    ).then((_) {
      // При возврате с экрана профиля перезагружаем данные
      _loadAllData();
    });
  }

  void _openDomainScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<MasqueradeBloc>(),
          child: const DomainsScreen(),
        ),
      ),
    );
  }

  void _openCarpetChat() {
    if (widget.profile.clan != 'Малкавиан' &&
        !widget.profile.isAdmin &&
        !widget.profile.isStoryteller) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Доступно только Малкавианам и администраторам')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CarpetChatScreen(profile: widget.profile),
      ),
    );
  }

  // ========== NEW: show document inline for web by creating an HTML overlay (no platformViewRegistry) ==========
  void _openDocumentOverlay() {
    // If not web — open in external browser (or native WebView screen)
    if (!kIsWeb) {
      // Mobile: open external browser as fallback (or push WebView-based screen)
      final uri = Uri.parse(_docEditUrl);
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    // If overlay already exists, do nothing
    if (html.document.getElementById('masq-doc-overlay') != null) return;

    // Save original body overflow
    final originalOverflow = html.document.body?.style.overflow ?? '';

    // Create overlay container
    final overlay = html.DivElement()
      ..id = 'masq-doc-overlay'
      ..style.position = 'fixed'
      ..style.top = '0'
      ..style.left = '0'
      ..style.width = '100vw'
      ..style.height = '100vh'
      ..style.backgroundColor = 'rgba(0,0,0,0.85)'
      ..style.zIndex = '999999'
      ..style.display = 'flex'
      ..style.flexDirection = 'column';

    // Header (title + actions)
    final header = html.DivElement()
      ..style.flex = '0 0 56px'
      ..style.display = 'flex'
      ..style.alignItems = 'center'
      ..style.justifyContent = 'space-between'
      ..style.padding = '8px 12px'
      ..style.background = 'linear-gradient(90deg, #4a0000, #2a0000)'
      ..style.color = '#FFD700';

    final title = html.DivElement()
      ..text = 'Документ'
      ..style.fontSize = '16px'
      ..style.fontWeight = '600';

    final actions = html.DivElement()
      ..style.display = 'flex'
      ..style.gap = '8px';

    final btnOpenNewTab = html.ButtonElement()
      ..text = 'Открыть в новой вкладке'
      ..style.padding = '6px 10px'
      ..style.background = '#2A2A2A'
      ..style.color = '#FFD700'
      ..style.border = 'none'
      ..style.borderRadius = '6px'
      ..style.cursor = 'pointer';

    final btnClose = html.ButtonElement()
      ..text = 'Закрыть'
      ..style.padding = '6px 10px'
      ..style.background = '#8B0000'
      ..style.color = '#FFF'
      ..style.border = 'none'
      ..style.borderRadius = '6px'
      ..style.cursor = 'pointer';

    actions.append(btnOpenNewTab);
    actions.append(btnClose);

    header.append(title);
    header.append(actions);

    // Iframe area
    final iframeContainer = html.DivElement()
      ..style.flex = '1 1 auto'
      ..style.position = 'relative'
      ..style.background = '#fff'
      ..style.margin = '12px'
      ..style.borderRadius = '8px'
      ..style.overflow = 'hidden';

    final iframe = html.IFrameElement()
      ..src = _docPreviewUrl
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block';

    iframeContainer.append(iframe);

    overlay.append(header);
    overlay.append(iframeContainer);

    // Append overlay to body
    html.document.body?.append(overlay);

    // Disable background scroll
    html.document.body?.style.overflow = 'hidden';

    // Event listeners
    btnClose.onClick.listen((_) {
      try {
        overlay.remove();
        html.document.body?.style.overflow = originalOverflow;
      } catch (_) {}
    });

    btnOpenNewTab.onClick.listen((_) {
      html.window.open(_docEditUrl, '_blank');
    });

    // Close overlay on ESC
    void escHandler(html.KeyboardEvent e) {
      if (e.key == 'Escape') {
        try {
          overlay.remove();
          html.document.body?.style.overflow = originalOverflow;
        } catch (_) {}
      }
    }

    html.window.addEventListener('keydown', escHandler as html.EventListener?);

    // When overlay removed manually, cleanup listener (we use a MutationObserver)
    final observer = html.MutationObserver((mutations, obs) {
      final exists = html.document.getElementById('masq-doc-overlay') != null;
      if (!exists) {
        try {
          html.window.removeEventListener('keydown', escHandler as html.EventListener?);
        } catch (_) {}
        try {
          obs.disconnect();
        } catch (_) {}
      }
    });

    observer.observe(html.document.body!, attributes: false, childList: true, subtree: false);
  }
  // ========== END overlay implementation ============================================================================

  IconData _getClanIcon(String clan) {
    switch (clan.toLowerCase()) {
      case 'ventrue':
        return Icons.coronavirus;
      case 'brujah':
        return Icons.flash_on;
      case 'toreador':
        return Icons.brush;
      case 'малкавиан':
      case 'Малкавиан':
        return Icons.psychology;
      case 'nosferatu':
        return Icons.visibility_off;
      case 'tremere':
        return Icons.auto_awesome;
      case 'gangrel':
        return Icons.pets;
      default:
        return Icons.question_mark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        // Если состояние AuthInitial (после выхода), перенаправляем на экран входа
        if (state is AuthInitial) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const EnterUsernameScreen()),
            (route) => false,
          );
        }
      },
      child: BlocListener<DomainBloc, DomainState>(
        listener: (context, state) {
          if (state is DomainsLoaded && !_neutralizationHandled) {
            final profileState = context.read<ProfileBloc>().state;
            if (profileState is ProfileLoaded) {
              final neutralizedDomains = state.domains.where((d) => d.isNeutral && d.ownerId == profileState.profile.id).toList();
              
              if (neutralizedDomains.isNotEmpty) {
                final remainingDomains = state.domains.where((d) => d.ownerId == profileState.profile.id && !d.isNeutral).toList();
                
                if (remainingDomains.isNotEmpty) {
                  _neutralizationHandled = true;
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const DomainsScreen()),
                  );
                }
              }
            }
          }
        },
        child: BlocProvider.value(
          value: context.read<MasqueradeBloc>(),
          child: BlocBuilder<ProfileBloc, ProfileState>(
            builder: (context, profileState) {
              if (profileState is! ProfileLoaded) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final profile = profileState.profile;

              // Проверяем, есть ли у пользователя домены
              final hasDomains = _domains != null &&
                  _domains!.any((domain) => domain.ownerId == profile.id);

              return Scaffold(
                appBar: AppBar(
                  title: const Text(
                    'Танкоград',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.white,
                      fontFamily: 'Gothic',
                      shadows: [
                        Shadow(
                          blurRadius: 4.0,
                          color: Colors.black,
                          offset: Offset(2.0, 2.0),
                        ),
                      ],
                    ),
                  ),
                  centerTitle: true,
                  backgroundColor: const Color(0xFF4A0000),
                  elevation: 0,
                  flexibleSpace: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A0000), Color(0xFF2A0000)],
                      ),
                    ),
                  ),
                  // leading теперь открывает встроенный просмотр документа (в PWA — overlay)
                  leading: IconButton(
                    icon: const Icon(Icons.menu_book, color: Colors.amber),
                    tooltip: 'Открыть документ',
                    onPressed: () {
                      _openDocumentOverlay();
                    },
                  ),

                  // кнопки справа: сначала (условно) чат, затем профиль
                  actions: [
                    if (profile.clan == 'Малкавиан' || profile.isAdmin || profile.isStoryteller)
                      IconButton(
                        icon: const Icon(Icons.chat, color: Colors.amber),
                        onPressed: _openCarpetChat,
                        tooltip: 'Гобелен',
                      ),
                    IconButton(
                      icon: const Icon(Icons.account_circle, color: Colors.amber),
                      onPressed: _openProfileScreen,
                      tooltip: 'Профиль',
                    ),
                  ],
                ),
                body: BlocListener<MasqueradeBloc, MasqueradeState>(
                  listener: (context, state) {
                    if (state is HuntCompleted) {
                      context.read<ProfileBloc>().add(UpdateHunger(state.newHunger));
                      if (state.violationOccurred) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Охота успешна! Но создано нарушение маскарада ',
                            ),
                            backgroundColor: Colors.amber[800],
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Охота прошла успешно! Голод уменьшен до ${state.newHunger}'),
                            backgroundColor: const Color(0xFF006400),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }

                    // Обработка ошибки нулевого голода при охоте
                    if (state is ViolationsError && state.message == 'hunt_with_zero_hunger') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Ваш голод уже утолён, охотиться незачем'),
                          backgroundColor: Colors.blue[800],
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }

                    
                  },
                  child: Stack(
                    children: [
                      // Сам виджет карты (без глобального Transform.rotate)
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _position != null
                              ? LatLng(_position!.latitude, _position!.longitude)
                              : const LatLng(55.751244, 37.618423),
                          initialZoom: 13,
                          interactionOptions: const InteractionOptions(
                            flags: ~InteractiveFlag.doubleTapDragZoom,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.masquerade.app',
                          ),
                          if (_position != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(
                                    _position!.latitude,
                                    _position!.longitude,
                                  ),
                                  width: 48,
                                  height: 48,
                                  child: Builder(builder: (context) {
                                    // Рассчитываем угол маркера так, чтобы он корректно показывал направление
                                    // относительного текущего поворота карты.
                                    final double compassDeg = _compassHeading ?? (_deviceOrientation * 180 / pi);
                                    final double markerAngleDeg = compassDeg + _mapRotationDegrees;
                                    final double markerAngleRad = (markerAngleDeg) * pi / 180;

                                    return Transform.rotate(
                                      angle: markerAngleRad,
                                      child: const Icon(
                                        Icons.navigation,
                                        color: Color(0xFFD4AF37),
                                        size: 48,
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                      ],
                    ),

                    if (_isLoadingLocation)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFD4AF37),
                            ),
                          ),
                        ),
                      ),

                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: _buildCharacterStatusBar(profile),
                    ),

                    // Кнопка центрирования — справа снизу, не перекрывает нижние действия
                    Positioned(
                      bottom: 100, // оставляем запас, чтобы не перекрывала нижние кнопки
                      right: 16,
                      child: FloatingActionButton(
                        heroTag: "center_btn",
                        backgroundColor: const Color(0xFF4A0000),
                        onPressed: () async {
                          if (_position == null) {
                            await _initLocation();
                          }
                          if (_position != null) {
                            // Получаем текущее направление устройства в градусах
                            final double deviceDeg = _compassHeading ?? (_deviceOrientation * 180 / pi);

                            // Значение, которое подаём в rotate: экспериментально может потребоваться сменить знак.
                            // Считаем, что нужно повернуть карту на -deviceDeg, чтобы направление устройства оказалось "вверх".
                            final double rotateToDeg = -deviceDeg;

                            try {
                              // Сохраняем состояние поворота (для корректного отображения маркера)
                              setState(() {
                                _mapRotationDegrees = rotateToDeg;
                              });

                              // Пытаемся вызвать rotate (в градусах)
                              try {
                                _mapController.rotate(rotateToDeg);
                              } catch (e) {
                                // Если метода rotate нет или он бросил — логируем и продолжаем
                              }

                              // Центрируем карту в любом случае
                              _mapController.move(LatLng(_position!.latitude, _position!.longitude), 15);
                            } catch (e) {
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Геолокация не определена')),
                            );
                          }
                        },
                        child: const Icon(Icons.my_location, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerFloat,
              floatingActionButton: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildActionButton(
                        icon: Icons.restaurant,
                        label: _isHuntCooldown() ? 'Ждите...' : 'Охотиться',
                        color: _isHuntCooldown() ? Colors.grey : const Color(0xFF8B0000),
                        onPressed: _isHuntCooldown() ? null : _onHuntWithCooldown,
                      ),
                      _buildActionButton(
                        icon: Icons.warning,
                        label: _isViolateCooldown() ? 'Ждите...' : 'Нарушить',
                        color: _isViolateCooldown() ? Colors.grey : const Color(0xFF4A0000),
                        onPressed: _isViolateCooldown() ? null : _onViolateWithCooldown,
                      ),
                      if (hasDomains) // Кнопка "Домен" появляется только если у пользователя есть домены
                        _buildActionButton(
                          icon: Icons.location_city,
                          label: _isDomainCooldown() ? 'Ждите...' : 'Домены',
                          color: _isDomainCooldown() ? Colors.grey : const Color(0xFF2A0000),
                          onPressed: _isDomainCooldown() ? null : _onDomainWithCooldown,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ));
  }

  // Виджет статус-бара персонажа
  Widget _buildCharacterStatusBar(ProfileModel profile) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        final currentProfile = (state is ProfileLoaded) ? state.profile : profile;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFD4AF37).withOpacity(0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD4AF37), width: 2),
                      color: Colors.black.withOpacity(0.5),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        getClanAvatarPath(profile.clan),
                        width: 30,
                        height: 30,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            _getClanIcon(profile.clan),
                            color: const Color(0xFFD4AF37),
                            size: 30,
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.characterName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.amber,
                          fontFamily: 'Gothic',
                          shadows: [
                            Shadow(
                              blurRadius: 6.0,
                              color: Colors.black,
                              offset: Offset(2.0, 2.0),
                            ),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${profile.clan}, ${profile.sect}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusIndicator(
                  icon: Icons.water_drop,
                  value: currentProfile.hunger,
                  color: const Color(0xFF8B0000),
                  max: 5,
                ),
                const SizedBox(width: 8),
                _buildStatusIndicator(
                  icon: Icons.star,
                  value: currentProfile.bloodPower,
                  color: const Color(0xFFB22222),
                  max: 10,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Виджет индикатора статуса
  Widget _buildStatusIndicator({
    required IconData icon,
    required int value,
    required Color color,
    required int max,
  }) {
    return Tooltip(
      message: '$value/$max',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              '$value',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Виджет кнопки действия
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: const Color(0xFFD4AF37), size: 24),
        label: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFD4AF37),
            fontWeight: FontWeight.bold,
            fontSize: 14,
            fontFamily: 'Gothic',
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.9),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
            side: BorderSide(color: const Color(0xFFD4AF37), width: 1.5),
          ),
          elevation: 5,
          shadowColor: Colors.black.withOpacity(0.5),
        ),
      ),
    );
  }

  Future<void> _reloadData() async {
    // Принудительно обновляем данные профиля
    context.read<ProfileBloc>().add(SetProfile(widget.profile));

    // Перезагружаем домены
    context.read<DomainBloc>().add(LoadDomains());
    context.read<DomainBloc>().add(RefreshDomains(widget.profile));

    // Перезагружаем нарушения
    context.read<MasqueradeBloc>().add(LoadViolations());

    // Обновляем геопозицию
    _initLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reloadData();
  }
}