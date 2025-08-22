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

  // Función para agregar solo nuevos eventos al local storage y devolver los nuevos eventos
  Future<List<Event>> mergeAndSaveEvents(List<Event> newEvents) async {
    // Obtener los eventos locales actuales
    Map<String, Event> localEvents = await getEvents();

    // Lista para almacenar los eventos nuevos
    List<Event> nuevosEventos = [];

    // Fusionar solo los eventos nuevos que no están en localEvents
    for (var event in newEvents) {
      String eventKey = _generateEventKey(event);
      if (!localEvents.containsKey(eventKey)) {
        localEvents[eventKey] = event; // Agregar solo los eventos nuevos
        nuevosEventos.add(event); // Añadir a la lista de nuevos eventos
      }
    }

    // Guardar la combinación actualizada en el local storage
    await saveEvents(localEvents);

    // Devolver los nuevos eventos
    return nuevosEventos;
  }

  // Función para marcar los eventos como leídos
  Future<void> markEventsAsRead(List<Event> eventsToMarkAsRead) async {
    // Obtener los eventos locales actuales
    Map<String, Event> localEvents = await getEvents();

    // Recorrer la lista de eventos que se deben marcar como leídos
    for (var eventToMark in eventsToMarkAsRead) {
      String eventKey = _generateEventKey(eventToMark);
      // Si el evento existe en el local storage, actualizar su atributo `isRead`
      if (localEvents.containsKey(eventKey)) {
        localEvents[eventKey]!.isRead = true;
      }
    }

    // Guardar los eventos actualizados en el local storage
    await saveEvents(localEvents);
  }

  // Función privada para generar la clave única
  String _generateEventKey(Event event) {
    return '${event.communityId}-${event.applicationId}-${event.contentId}';
  }
}
