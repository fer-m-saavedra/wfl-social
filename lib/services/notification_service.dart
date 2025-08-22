import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_app_badge/flutter_app_badge.dart';
import 'data_service.dart';
import 'auth_service.dart';
import '../services/event_sqlite_service.dart';

class NotificationService {
  final DataService dataService;
  final AuthService authService;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  NotificationService({
    required this.dataService,
    required this.authService,
    required this.flutterLocalNotificationsPlugin,
  });

  /// Sincroniza con fetchData2, detecta qué eventos se insertaron en SQLite
  /// y notifica sólo esos. Luego actualiza el badge con el total no leído.
  Future<void> checkForNewNotifications() async {
    try {
      final session = await authService.getSession();
      if (session == null || session.username.isEmpty) {
        print('No se encontró una sesión válida...');
        return;
      }

      // 1) Snapshot "antes" (keys existentes)
      final evDb = EventSqliteService();
      await evDb.init();
      final beforeRows = await evDb.getAll(orderBy: null);
      final beforeKeys = _toKeySet(beforeRows);

      // 2) Sincroniza: trae Nivel1..5 y hace insert IGNORE en SQLite
      final empresaIndex = (await dataService.fetchData2(session.username))
          as Map<String, dynamic>;

      // 3) Snapshot "después" (keys existentes)
      final afterRows = await evDb.getAll(orderBy: null);
      final afterKeys = _toKeySet(afterRows);

      // 4) Diferencia = NUEVOS (insertados)
      final newKeys = afterKeys.difference(beforeKeys);
      final newEvents = <Map<String, dynamic>>[];

      if (newKeys.isNotEmpty) {
        // Para cada key nueva, levanto la fila completa (contenido/fecha)
        for (final k in newKeys) {
          final parts = k.split('|');
          if (parts.length != 5) continue;
          final empId = int.parse(parts[0]);
          final tipoId = int.parse(parts[1]);
          final comunidadId = int.parse(parts[2]);
          final aplicacionId = int.parse(parts[3]);
          final contenidoId = int.parse(parts[4]);

          final rows = await evDb.getAll(
            empId: empId,
            tipoId: tipoId,
            comunidadId: comunidadId,
            aplicacionId: aplicacionId,
          );

          // Busco la fila exacta por contenidoId
          final row = rows.firstWhere(
            (r) => (r['contenidoId'] as int) == contenidoId,
            orElse: () => {},
          );
          if (row.isNotEmpty) {
            newEvents.add(row);
          }
        }
      }

      // 5) Notificar según cantidad
      if (newEvents.isNotEmpty) {
        if (newEvents.length > 5) {
          await _showBulkNotification(newEvents.length);
        } else {
          await _showIndividualNotifications(newEvents, empresaIndex);
        }
      } else {
        print('No hay nuevas notificaciones');
      }

      // 6) Actualizar badge con total de NO leídos real
      final unreadTotal = await evDb.countUnread();
      await FlutterAppBadge.count(unreadTotal);
    } catch (e) {
      print('Error al obtener notificaciones: $e');
    }
  }

  // ========= Helpers de notificaciones =========

  Future<void> _showBulkNotification(int eventCount) async {
    final android = AndroidNotificationDetails(
      'events_channel',
      'Eventos',
      channelDescription: 'Notificaciones de nuevos eventos',
      importance: Importance.max,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: android);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Nuevos eventos',
      'Hay $eventCount nuevos eventos.',
      details,
    );
  }

  /// Muestra una notificación por cada evento NUEVO insertado.
  /// Usa empresaIndex para armar títulos legibles.
  Future<void> _showIndividualNotifications(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> empresaIndex,
  ) async {
    int notifId = 1;
    for (final r in rows) {
      final empId = (r['empId'] as int);
      final tipoId = (r['tipoId'] as int);
      final conceptoId = (r['comunidadId'] as int);
      final aplicacionId = (r['aplicacionId'] as int);
      final contenido = (r['contenido'] ?? '').toString();
      final fechaIso = (r['fecha'] ?? '').toString();

      final names = _resolveNames(
        empresaIndex: empresaIndex,
        empId: empId,
        tipoId: tipoId,
        conceptoId: conceptoId,
        aplicacionId: aplicacionId,
      );

      final title =
          '${names.concepto} - ${names.aplicacion} - ${_fmtDate(fechaIso)}';

      final android = AndroidNotificationDetails(
        'events_channel',
        'Eventos',
        channelDescription: 'Notificaciones de nuevos eventos',
        importance: Importance.max,
        priority: Priority.high,
      );
      final details = NotificationDetails(android: android);

      await flutterLocalNotificationsPlugin.show(
        notifId++,
        title,
        contenido,
        details,
      );
    }
  }

  // ========= Utilidades =========

  /// Convierte filas de events en un set de claves únicas
  Set<String> _toKeySet(List<Map<String, dynamic>> rows) {
    final s = <String>{};
    for (final r in rows) {
      s.add(
          '${r['empId']}|${r['tipoId']}|${r['comunidadId']}|${r['aplicacionId']}|${r['contenidoId']}');
    }
    return s;
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$d-$m-$y';
    } catch (_) {
      return iso;
    }
  }
}

/// Resuelve nombres legibles desde empresaIndex
class _ResolvedNames {
  final String concepto;
  final String aplicacion;
  _ResolvedNames(this.concepto, this.aplicacion);
}

_ResolvedNames _resolveNames({
  required Map<String, dynamic> empresaIndex,
  required int empId,
  required int tipoId,
  required int conceptoId,
  required int aplicacionId,
}) {
  final emp = empresaIndex['$empId'] as Map<String, dynamic>?;
  final tipo = (emp?['tipos'] as Map<String, dynamic>?)?['$tipoId']
      as Map<String, dynamic>?;
  final concepto = (tipo?['conceptos'] as Map<String, dynamic>?)?['$conceptoId']
      as Map<String, dynamic>?;
  final apps = (concepto?['aplicaciones'] as Map<String, dynamic>?) ?? {};
  final app = apps['$aplicacionId'] as Map<String, dynamic>?;

  final conceptoName =
      (concepto?['Concepto'] ?? 'Concepto $conceptoId').toString();
  // El campo puede variar según tu API; ajusta si es distinto
  final appName = (app?['Aplicacion'] ?? 'App $aplicacionId').toString();

  return _ResolvedNames(conceptoName, appName);
}
