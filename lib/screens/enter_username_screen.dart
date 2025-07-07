import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/auth/auth_bloc.dart';

class EnterUsernameScreen extends StatefulWidget {
  const EnterUsernameScreen({Key? key}) : super(key: key);

  @override
  _EnterUsernameScreenState createState() => _EnterUsernameScreenState();
}

class _EnterUsernameScreenState extends State<EnterUsernameScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  void _submit() {
    final username = _controller.text.trim().replaceFirst('@', '');
    if (username.isEmpty) {
      setState(() {
        _error = 'Пожалуйста, введите имя пользователя без @';
      });
      return;
    }

    context.read<AuthBloc>().add(UsernameSubmitted(username));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthFailure) {
            setState(() {
              _error =
                  'Ваше имя пользователя отсутствует в списках, пожалуйста, обратитесь к администратору';
            });
          }
        },
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Введите ваш Telegram username',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Это имя, которое начинается с @ в вашем Telegram профиле.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: '@username',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: state is AuthLoading ? null : _submit,
                  child: const Text('Войти'),
                ),
                if (_error != null && _error!.contains('отсутствует'))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton(
                      onPressed: () {
                        // открыть Telegram ссылку
                        // URL launcher будет добавлен в main позже
                      },
                      child: const Text(
                        'Связаться с администратором',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
