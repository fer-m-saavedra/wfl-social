import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/community.dart';
import '../models/application.dart';
import '../models/event.dart';
import 'storage_service.dart';
import 'config_service.dart';
import '../services/encryption_service.dart';

class DataService {
  final StorageService storageService;
  late final EncryptionService _encryptionService;

  DataService({required this.storageService}) {
    _encryptionService = EncryptionService(
      passPhrase: ConfigService.secPassPhraseApi ?? '',
      saltValue: ConfigService.secSaltValueApi ?? '',
      initVector: ConfigService.secInitVectorApi ?? '',
    );
  }

  Future<Map<String, dynamic>> fetchData(String username) async {
    final apiUrl = ConfigService.apiUrlEventos;
    if (apiUrl == null) {
      throw Exception('La URL del servicio de eventos no está configurada.');
    }

    final session = await storageService.getSession();
    final lastConnection = session?.lastEventFetch ?? DateTime.now().toString();
    final encryptedUsername = _encryptionService.encryptAES(username);

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer ${session?.token ?? ''}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(
          {'UserCod': encryptedUsername, 'UltimaConexionApp': lastConnection}),
    );

    if (response.statusCode == 200) {
      final dataEncrypt = _encryptionService.decryptAES(response.body);
      final data = json.decode(dataEncrypt);

      List<Community> communities = (data['Comunidades'] as List)
          .map((json) => Community.fromJson(json))
          .toList();

      List<Application> applications = (data['Aplicaciones'] as List)
          .map((json) => Application.fromJson(json))
          .toList();

      List<Event> newEvents = (data['Eventos'] as List)
          .map((json) => Event.fromJson(json))
          .toList();

      final newSession =
          session?.copyWith(lastEventFetch: DateTime.now().toString());
      if (newSession != null) {
        await storageService.saveSession(newSession);
      }

      // Usamos la función modificada para obtener y guardar los nuevos eventos
      List<Event> onlyNewEvents =
          await storageService.mergeAndSaveEvents(newEvents);

      Map<String, Event> localEvents = await storageService.getEvents();

      return {
        'communities': communities,
        'applications': applications,
        'events': localEvents.values.toList(),
        'newEvents': onlyNewEvents, // Retornamos los nuevos eventos
      };
    } else {
      throw Exception('Error al obtener los datos: ${response.statusCode}');
    }
  }

  Future<void> clearLocalData() async {
    await storageService.saveEvents({});
  }
}
