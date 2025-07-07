import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _checking = false;

  Future<void> _requestPermission() async {
    setState(() => _checking = true);

    final permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Геолокация')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _checking
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, size: 72, color: Colors.blue),
                    const SizedBox(height: 16),
                    const Text(
                      'Приложению требуется доступ к геопозиции для работы.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _requestPermission,
                      icon: const Icon(Icons.gps_fixed),
                      label: const Text('Разрешить доступ'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
