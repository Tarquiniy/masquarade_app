import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/blocs/auth/auth_bloc.dart';

import 'package:masquarade_app/blocs/profile/profile_bloc.dart';
import 'package:masquarade_app/models/domain_model.dart';
import 'package:masquarade_app/models/profile_model.dart';
import 'package:masquarade_app/repositories/supabase_repository.dart';
import 'package:masquarade_app/screens/coin_flip_screen.dart';
import 'package:masquarade_app/utils/debug_telegram.dart';
import 'package:masquarade_app/utils/clan_utils.dart';

class ProfileScreen extends StatefulWidget {
  final ProfileModel profile;

  const ProfileScreen({super.key, required this.profile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  int? _previousHunger;
  bool _isFirstBuild = true;
  ProfileModel? _selectedPlayerForAura;
  List<DomainModel> _allDomains = [];
  DateTime? _lastDisciplinePressed;
  Timer? _disciplineCooldownTimer;
  bool _isDisciplineCooldownActive = false;
  
  // Новые переменные для поиска и сортировки
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sortAscending = true;
  List<ProfileModel> _allPlayers = [];

  @override
  void dispose() {
    _disciplineCooldownTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isDisciplineOnCooldown => _isDisciplineCooldownActive;

  // Упрощенный запуск кулдауна
  void _startDisciplineCooldown() {
    setState(() {
      _lastDisciplinePressed = DateTime.now();
      _isDisciplineCooldownActive = true;
    });

    _disciplineCooldownTimer?.cancel();
    _disciplineCooldownTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        _isDisciplineCooldownActive = false;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _previousHunger = widget.profile.hunger;
    _loadDomains();
    _loadAllPlayers();
  }

  Future<void> _loadDomains() async {
    {
      final repository = RepositoryProvider.of<SupabaseRepository>(context);
      _allDomains = await repository.getDomains();
      setState(() {});
    } 
  }

  Future<void> _loadAllPlayers() async {
    {
      final players = await context.read<ProfileBloc>().getPlayers();
      setState(() {
        _allPlayers = players;
      });
    }
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFF1a0000),
    body: BlocListener<ProfileBloc, ProfileState>(
      listener: (context, state) {
        if (state is ProfileLoaded) {
          if (!_isFirstBuild &&
              _previousHunger != null &&
              state.profile.hunger > _previousHunger!) {

            final increase = state.profile.hunger - _previousHunger!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Голод увеличен на $increase'),
                backgroundColor: Colors.red[800],
                duration: const Duration(seconds: 2),
              ),
            );
          }

          _previousHunger = state.profile.hunger;
          _isFirstBuild = false;
        }
      },
      child: BlocListener<AuthBloc, AuthState>(
        listener: (context, authState) {
          if (authState is AuthInitial) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1a0000), Color(0xFF2a0000)],
            ),
          ),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 150.0,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    widget.profile.characterName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 10.0, color: Colors.black)],
                    ),
                  ),
                  centerTitle: true,
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/vtm_background.jpg',
                        fit: BoxFit.cover,
                        color: Colors.black.withOpacity(0.7),
                        colorBlendMode: BlendMode.darken,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    onPressed: () => _confirmLogout(context),
                    tooltip: 'Выйти',
                  ),
                ],
                backgroundColor: const Color(0xFF1a0000),
              ),
              _buildContent(context),
              _buildPillarsSection(context),
              _buildDisciplinesSection(context),
              _buildAuraRequestSection(context),
              _buildCoinFlipSection(context),
            ],
          ),
        ),
      ),
    ),
  );
}

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Подтверждение выхода'),
        content: const Text('Вы уверены, что хотите выйти из профиля?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthBloc>().add(LogoutRequested());
            },
            child: const Text('Выйти', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          _buildCharacterInfo(context),
          const SizedBox(height: 24),
          _buildStatsSection(context),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _buildCharacterInfo(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        final profile = (state is ProfileLoaded) ? state.profile : widget.profile;

        return Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ИНФОРМАЦИЯ О ПЕРСОНАЖЕ',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Divider(color: Color(0xFF8b0000), height: 24),
                _buildClanRow(profile.clan), // Изменено на специальный метод для клана
                _buildInfoRow('Секта', profile.sect, Icons.group),
                _buildInfoRow('Роль', profile.role, Icons.security),
                _buildInfoRow('Человечность', profile.humanity.toString(), Icons.psychology),
              ],
            ),
          ),
        );
      },
    );
  }

  // Новый метод для отображения строки с аватаркой клана
  Widget _buildClanRow(String clanName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset(
              getClanAvatarPath(clanName),
              width: 20,
              height: 20,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Icon(Icons.bloodtype, color: const Color(0xFFd4af37), size: 20);
              },
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Клан: ',
            style: const TextStyle(
              color: Color(0xFFd4af37),
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              clanName,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFd4af37), size: 20),
          const SizedBox(width: 12),
          Text(
            '$title: ',
            style: const TextStyle(
              color: Color(0xFFd4af37),
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, profileState) {
        final currentProfile = (profileState is ProfileLoaded)
            ? profileState.profile
            : widget.profile;


        return Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ХАРАКТЕРИСТИКИ',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2),
                  ),
                const Divider(color: Color(0xFF8b0000), height: 24),
                _buildStatValue(
                  'Сила крови',
                  '${currentProfile.bloodPower}',
                  Icons.whatshot,
                ),
                _buildStatValue(
                'Поколение',
                '${currentProfile.generation}',
                Icons.linear_scale,
              ),
                _buildStatBar(
                  'Голод',
                  currentProfile.hunger,
                  5,
                  Icons.local_dining,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDisciplinesSection(BuildContext context) {
  return BlocBuilder<ProfileBloc, ProfileState>(
    builder: (context, state) {
      final profile = (state is ProfileLoaded) ? state.profile : widget.profile;

      return SliverPadding(
        padding: const EdgeInsets.all(16.0),
        sliver: SliverToBoxAdapter(
          child: Card(
            color: const Color(0xFF2a0000).withOpacity(0.8),
            elevation: 5,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: const BorderSide(color: Color(0xFF8b0000), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFd4af37)),
                      SizedBox(width: 8),
                      Text(
                        'ДИСЦИПЛИНЫ',
                        style: TextStyle(
                          color: Color(0xFFd4af37),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF8b0000), height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: profile.disciplines
                        .map((d) => _buildDisciplineButton(d, profile))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

  Widget _buildDisciplineButton(String discipline, ProfileModel profile) {
    Color buttonColor = _getDisciplineColor(_getDisciplineCost(discipline));
    bool isCooldown = _isDisciplineOnCooldown;

    if (discipline == 'Регенерация' || discipline == 'Прочее') {
      buttonColor = const Color.fromARGB(255, 225, 4, 4);
    }

    return ElevatedButton(
      onPressed: isCooldown
          ? null
          : () {
              _useDiscipline(discipline, _getDisciplineCost(discipline), profile);
              _startDisciplineCooldown();
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: isCooldown ? Colors.grey : buttonColor,
        foregroundColor: isCooldown ? Colors.white : Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      child: Text(discipline),
    );
  }

  int _getDisciplineCost(String discipline) {
    if (discipline == 'Регенерация' || discipline == 'Прочее') {
    return 1;
  }
    if (discipline.endsWith(' 2')) return 1;
    if (discipline.endsWith(' 3')) return 2;
    return 0;
  }

  Color _getDisciplineColor(int cost) {
    switch (cost) {
      case 1: return Colors.amber;
      case 2: return Colors.orange;
      case 3: return Colors.red;
      default: return Colors.grey;
    }
  }

  Future<void> _useDiscipline(
  String discipline,
  int hungerCost,
  ProfileModel currentProfile
) async {
  final newHunger = currentProfile.hunger + hungerCost;

  if (newHunger > 5) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Невозможно использовать дисциплину: максимальный голод (5) будет превышен'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
    return;
  }

    try {
      final repository = RepositoryProvider.of<SupabaseRepository>(context);
      final updatedHunger = await repository.updateHunger(
        currentProfile.id,
        newHunger
      );

      if (updatedHunger != null) {
        context.read<ProfileBloc>().add(UpdateHunger(updatedHunger));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Использована $discipline. Голод +$hungerCost'),
            backgroundColor: Colors.red[800],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка обновления голода')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Widget _buildStatValue(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFd4af37), size: 20),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              color: Color(0xFFd4af37),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ));
  }

  Widget _buildStatBar(String label, int value, int max, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFd4af37), size: 20),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFd4af37),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '$value/$max',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: value / max,
            backgroundColor: Colors.grey[800],
            color: value < max / 2
                ? const Color(0xFF8b0000)
                : const Color(0xFFd4af37),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      )
    );
  }

  Widget _buildAuraRequestSection(BuildContext context) {
    final hasAuspex2 = widget.profile.disciplines.contains('Прорицание 2');

    if (!hasAuspex2) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverToBoxAdapter(
        child: Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color.fromARGB(255, 84, 6, 6), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ЗАПРОС АУРЫ',
                  style: TextStyle(
                    color: Color(0xFFd4af37),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const Divider(color: Color(0xFF8b0000), height: 24),
                
                // Строка с поиском и сортировкой
                Row(
                  children: [
                    // Кнопка сортировки с текстом (измененная часть)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF8b0000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            _sortAscending = !_sortAscending;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                color: const Color(0xFFd4af37),
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _sortAscending ? 'А-я' : 'Я-а',
                                style: const TextStyle(
                                  color: Color(0xFFd4af37),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Поле поиска
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Поиск игрока...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        _searchQuery = '';
                                        _searchController.clear();
                                      });
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                const Text(
                  'Выберите персонажа для чтения ауры:',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                
                // Список игроков с поиском и сортировкой
                _buildPlayerSelector(context),
                
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedPlayerForAura != null
                        ? () => _sendAuraRequest(context, _selectedPlayerForAura!)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedPlayerForAura != null 
                          ? Colors.purple[800] 
                          : Colors.grey[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ОТПРАВИТЬ ЗАПРОС АУРЫ',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerSelector(BuildContext context) {
    // Фильтрация игроков по поисковому запросу
    List<ProfileModel> filteredPlayers = _allPlayers.where((player) {
      return player.characterName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             player.clan.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             player.sect.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // Сортировка по алфавиту
    filteredPlayers.sort((a, b) {
      int comparison = a.characterName.compareTo(b.characterName);
      return _sortAscending ? comparison : -comparison;
    });

    // Исключаем текущего пользователя
    filteredPlayers = filteredPlayers.where((player) => player.id != widget.profile.id).toList();

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1a0000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8b0000), width: 1),
      ),
      child: filteredPlayers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, color: Colors.grey, size: 40),
                  const SizedBox(height: 8),
                  Text(
                    _searchQuery.isEmpty ? 'Нет доступных игроков' : 'Игроки не найдены',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: filteredPlayers.length,
              itemBuilder: (context, index) {
                final player = filteredPlayers[index];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: _selectedPlayerForAura?.id == player.id
                        ? Colors.purple[800]?.withOpacity(0.3)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: _selectedPlayerForAura?.id == player.id
                        ? Border.all(color: Colors.purple, width: 1)
                        : null,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF8b0000),
                      child: Text(
                        player.characterName[0].toUpperCase(),
                        style: const TextStyle(color: Color(0xFFd4af37)),
                      ),
                    ),
                    title: Text(
                      player.characterName,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    subtitle: Text(
                      '${player.clan}, ${player.sect}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    trailing: _selectedPlayerForAura?.id == player.id
                        ? const Icon(Icons.check_circle, color: Colors.purple, size: 20)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedPlayerForAura = player;
                      });
                    },
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildPillarsSection(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        final profile = (state is ProfileLoaded) ? state.profile : widget.profile;

        return SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverToBoxAdapter(
            child: Card(
              color: const Color(0xFF2a0000).withOpacity(0.8),
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: const BorderSide(color: Color(0xFF8b0000), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'СТОЛПЫ ЛИЧНОСТИ',
                      style: TextStyle(
                        color: Color(0xFFd4af37),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Divider(color: Color(0xFF8b0000), height: 24),
                    ...profile.pillars
                        .map((pillar) => _buildPillarTile(context, pillar))
                        .toList(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPillarTile(BuildContext context, Map<String, dynamic> pillar) {
    return ListTile(
      title: Text(
        pillar['name'] ?? 'Неизвестный столп',
        style: const TextStyle(
          color: Color(0xFFd4af37),
        ),
      ),
      subtitle: Text(
        pillar['description'] ?? 'Описание отсутствует',
        style: const TextStyle(color: Colors.white70),
      ),
      onLongPress: () {
        _showDestroyPillarDialog(context, pillar);
      },
    );
  }

  void _showDestroyPillarDialog(
    BuildContext context,
    Map<String, dynamic> pillar,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обрушить столп?'),
        content: Text(
          'Вы уверены, что хотите обрушить столп "${pillar['name']}"? '
          'Это действие необратимо и уменьшит вашу Человечность.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _destroyPillar(context, pillar);
            },
            child: const Text('Обрушить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _destroyPillar(BuildContext context, Map<String, dynamic> pillar) {
    context.read<ProfileBloc>().add(DestroyPillar(pillar['name']));
  }

  Widget _buildCoinFlipSection(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverToBoxAdapter(
        child: Card(
          color: const Color(0xFF2a0000).withOpacity(0.8),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFF8b0000), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CoinFlipScreen()),
                    );
                  },
                  icon: const Icon(Icons.monetization_on, color: Colors.amber),
                  label: Text(
                    'Подбросить монетку',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                    backgroundColor: const Color(0xFF8b0000),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _sendAuraRequest(BuildContext context, ProfileModel target) {
    sendTelegramMode(
       chatId: '369397714', message: '📡 Запрос ауры\n'
      'От: ${widget.profile.characterName} (${widget.profile.external_name})\n'
      'Персонаж: ${target.characterName}\n'
      'Username: ${target.external_name}', mode: 'debug',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Запрос ауры на ${target.characterName} отправлен'),
        backgroundColor: Colors.purple,
      ),
    );
  }

}