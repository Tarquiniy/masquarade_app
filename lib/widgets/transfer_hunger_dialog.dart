import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/profile/profile_bloc.dart';
import '../models/profile_model.dart';
import '../repositories/supabase_repository.dart';

//class TransferHungerDialog extends StatefulWidget {
//  const TransferHungerDialog({super.key});

//  @override
//  State<TransferHungerDialog> createState() => _TransferHungerDialogState();
//}

//class _TransferHungerDialogState extends State<TransferHungerDialog> {
//  int _points = 1;
//  String? _selectedPlayerId;
//  List<ProfileModel> _availablePlayers = [];
//  bool _loading = true;

//  @override
//  void initState() {
//    super.initState();
//    _loadPlayers();
//  }

//  Future<void> _loadPlayers() async {
//    final profileState = context.read<ProfileBloc>().state;
//    if (profileState is! ProfileLoaded) return;

//    final currentId = profileState.profile.id;
//    final all = await context.read<SupabaseRepository>().getAllProfiles();

//    setState(() {
//      _availablePlayers = all.where((p) => p.id != currentId).toList();
//      _loading = false;
//    });
//  }

  //Future<void> _transfer() async {
  //  final profileState = context.read<ProfileBloc>().state;
  //  if (profileState is! ProfileLoaded) return;

    //final profile = profileState.profile;

    //if (_selectedPlayerId == null) {
      //_showError('Выберите получателя');
      //return;
    //}

    //if (_points > profile.hunger) {
    //  _showError('У вас недостаточно голода');
    //  return;
    //}

    //try {
    //  await context.read<SupabaseRepository>().transferHunger(
    //    fromUserId: profile.id,
    //    toUserId: _selectedPlayerId!,
    //    amount: _points,
    //  );

    //  final updated = profile.copyWith(hunger: profile.hunger - _points);
    //  context.read<ProfileBloc>().add(UpdateProfile(updated));

    //  if (mounted) Navigator.pop(context);
    //} catch (e) {
    //  _showError('Ошибка передачи: ${e.toString()}');
    //}
  //}

  //void _showError(String msg) {
  //  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  //}

  //@override
  //Widget build(BuildContext context) {
  //  return AlertDialog(
  //    title: const Text('Передача голода'),
  //    content: _loading
  //        ? const SizedBox(
  //            height: 100,
  //            child: Center(child: CircularProgressIndicator()),
  //          )
  //        : Column(
  //            mainAxisSize: MainAxisSize.min,
  //            children: [
  //              const Text('Кому передать:'),
  //              const SizedBox(height: 8),
  //              DropdownButtonFormField<String>(
  //                isExpanded: true,
  //                value: _selectedPlayerId,
  //                items: _availablePlayers
  //                    .map(
  //                      (p) => DropdownMenuItem(
  //                        value: p.id,
  //                       child: Text(p.characterName),
  //                      ),
  //                    )
  //                    .toList(),
  //                onChanged: (value) =>
  //                    setState(() => _selectedPlayerId = value),
  //                decoration: const InputDecoration(
  //                  border: OutlineInputBorder(),
  //                ),
  //              ),
  //              const SizedBox(height: 12),
  //              const Text('Пункты голода:'),
  //              Row(
  //                mainAxisAlignment: MainAxisAlignment.center,
  //                children: [
  //                  IconButton(
  //                    onPressed: _points > 1
  //                        ? () => setState(() => _points--)
  //                        : null,
  //                    icon: const Icon(Icons.remove),
  //                  ),
  //                  Text('$_points'),
  //                  IconButton(
  //                    onPressed: () => setState(() => _points++),
  //                    icon: const Icon(Icons.add),
  //                  ),
  //                ],
  //              ),
  //            ],
  //          ),
  //    actions: [
  //      TextButton(
  //        onPressed: Navigator.of(context).pop,
  //        child: const Text('Отмена'),
  //      ),
  //      ElevatedButton(onPressed: _transfer, child: const Text('Передать')),
  //    ],
  //  );
  //}
  //}
