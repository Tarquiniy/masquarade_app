import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class OrientationPlugin {
  static Stream<DeviceOrientation>? get orientationEvents {
    if (kIsWeb) {
      return _webOrientationEvents;
    }
    return null;
  }

  static Stream<DeviceOrientation>? _webOrientationEvents;

  static Stream<DeviceOrientation> get _initWebOrientation {
    final controller = StreamController<DeviceOrientation>();
    
    // Проверяем поддержку DeviceOrientation через проверку наличия обработчика событий
    final isSupported = html.window.onDeviceOrientation != null;
    
    if (isSupported) {
      html.window.addEventListener('deviceorientation', (event) {
        if (event is html.DeviceOrientationEvent) {
          // Инвертируем значения для правильного направления вращения
          controller.add(DeviceOrientation(
            yaw: -(event.alpha ?? 0).toDouble(), // Инвертируем для правильного направления
            pitch: (event.beta ?? 0).toDouble(),
            roll: (event.gamma ?? 0).toDouble(),
          ));
        }
      });
    } else {
      // Fallback для браузеров без поддержки DeviceOrientation
      controller.add(DeviceOrientation(yaw: 0, pitch: 0, roll: 0));
    }

    return controller.stream;
  }

  static void initialize() {
    _webOrientationEvents ??= _initWebOrientation;
  }
}

class DeviceOrientation {
  final double yaw;
  final double pitch;
  final double roll;

  DeviceOrientation({
    required this.yaw,
    required this.pitch,
    required this.roll,
  });
}