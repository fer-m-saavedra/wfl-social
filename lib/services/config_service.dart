import 'dart:convert';
import 'package:flutter/services.dart';

class ConfigService {
  static Map<String, dynamic>? _config;

  static Future<void> loadConfig() async {
    final configString =
        await rootBundle.loadString('assets/config/config.json');
    _config = json.decode(configString);
  }

  // URLs para los servicios de API
  static String? get apiUrlEventos => _config?['apiUrlEventos'];
  static String? get apiUrlEventos2 => _config?['apiUrlEventos2'];

  static String? get apiUrlLogin => _config?['apiUrlLogin'];

  // Claves para encriptación
  static String? get secPassPhraseApi => _config?['secPassPhraseApi'];
  static String? get secSaltValueApi => _config?['secSaltValueApi'];
  static String? get secInitVectorApi => _config?['secInitVectorApi'];

  // Otros valores
  static int get sessionMaxLifetimeMinutes =>
      _config?['sessionMaxLifetimeMinutes'] ?? 60;
}
