import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:masquarade_app/blocs/auth/auth_bloc.dart';

class EnterUsernameScreen extends StatelessWidget {
  const EnterUsernameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final _usernameController = TextEditingController();

    return Scaffold(
      backgroundColor: const Color(0xFF1a0000),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Vampire: The Masquerade:',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFd4af37),
                ),
              ),
              const Text(
                'Танкоград',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 253, 1, 1),
                ),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _usernameController,
                style: const TextStyle(color: Colors.white70),
                decoration: InputDecoration(
                  labelText: 'Telegram username без @',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Color(0xFF8b0000)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(
                      color: Color(0xFFd4af37),
                      width: 2,
                    ),
                  ),
                  prefixIcon: const Icon(Icons.person, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),
              BlocConsumer<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state is AuthFailure) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка: ${state.message}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                builder: (context, state) {
                  return ElevatedButton(
                    onPressed: state is AuthLoading
                        ? null
                        : () {
                            if (_usernameController.text.isNotEmpty) {
                              context.read<AuthBloc>().add(
                                UsernameSubmitted(_usernameController.text.trim()),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8b0000),
                      foregroundColor: const Color(0xFFd4af37),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: state is AuthLoading
                        ? const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFd4af37),
                            ),
                          )
                        : const Text(
                            'Войти',
                            style: TextStyle(fontSize: 18),
                          ),
                  );
                },
              ),
              const SizedBox(height: 20),
              
            ],
          ),
        ),
      ),
    );
  }
}