import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import '../models/company_event.dart';
import '../models/session.dart';
import '../models/company.dart';

class StorageService {
  static const String _eventsKey = 'events';
  static const String _sessionKey = 'session';
  static const String _companyEventsKey = 'company_events';
  static const String _empresaIndexKey = 'company';

  // Nuevas claves para credenciales guardadas
  static const String _credUserKey = 'cred_user';
  static const String _credPassEncKey = 'cred_pass_enc';

  Future<void> saveSession(Session session) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String sessionJson = jsonEncode(session.toJson());
    await prefs.setString(_sessionKey, sessionJson);
  }

  Future<Session?> getSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? sessionJson = prefs.getString(_sessionKey);
    if (sessionJson != null) {
      Map<String, dynamic> sessionMap = jsonDecode(sessionJson);
      return Session.fromJson(sessionMap);
    }
    return null;
  }

  Future<void> removeSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  Future<void> saveEvents(Map<String, Event> events) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, String> eventStrings =
        events.map((key, event) => MapEntry(key, jsonEncode(event.toJson())));
    await prefs.setString(_eventsKey, jsonEncode(eventStrings));
  }

  Future<Map<String, Event>> getEvents() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? eventMapString = prefs.getString(_eventsKey);
    if (eventMapString == null) {
      return {};
    }

    Map<String, dynamic> eventMap = jsonDecode(eventMapString);
    return eventMap.map((key, eventJson) =>
        MapEntry(key, Event.fromJson(jsonDecode(eventJson))));
  }

  // Fusiona y retorna solo los nuevos eventos
  Future<List<Event>> mergeAndSaveEvents(List<Event> newEvents) async {
    Map<String, Event> localEvents = await getEvents();
    List<Event> nuevosEventos = [];

    for (var event in newEvents) {
      String eventKey = _generateEventKey(event);
      if (!localEvents.containsKey(eventKey)) {
        localEvents[eventKey] = event;
        nuevosEventos.add(event);
      }
    }

    await saveEvents(localEvents);
    return nuevosEventos;
  }

  Future<void> markEventsAsRead(List<Event> eventsToMarkAsRead) async {
    Map<String, Event> localEvents = await getEvents();

    for (var eventToMark in eventsToMarkAsRead) {
      String eventKey = _generateEventKey(eventToMark);
      if (localEvents.containsKey(eventKey)) {
        localEvents[eventKey]!.isRead = true;
      }
    }

    await saveEvents(localEvents);
  }

  String _generateEventKey(Event event) {
    return '${event.communityId}-${event.applicationId}-${event.contentId}';
  }

  // ====== CREDENCIALES GUARDADAS ======

  /// Guarda usuario (en claro) y contraseña encriptada.
  Future<void> saveEncryptedCredentials({
    required String username,
    required String encryptedPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_credUserKey, username);
    await prefs.setString(_credPassEncKey, encryptedPassword);
  }

  /// Devuelve (username, encryptedPassword) si existen.
  Future<_SavedCreds?> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final u = prefs.getString(_credUserKey);
    final p = prefs.getString(_credPassEncKey);
    if (u == null || u.isEmpty || p == null || p.isEmpty) return null;
    return _SavedCreds(username: u, encryptedPassword: p);
  }

  /// Borra las credenciales guardadas.
  Future<void> removeSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_credUserKey);
    await prefs.remove(_credPassEncKey);
  }
}

class _SavedCreds {
  final String username;
  final String encryptedPassword;
  _SavedCreds({required this.username, required this.encryptedPassword});
}
