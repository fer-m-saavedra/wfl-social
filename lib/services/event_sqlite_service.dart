import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class EventSqliteService {
  static final EventSqliteService _i = EventSqliteService._internal();
  factory EventSqliteService() => _i;
  EventSqliteService._internal();

  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'events.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            empId INTEGER NOT NULL,
            tipoId INTEGER NOT NULL,
            comunidadId INTEGER NOT NULL,
            aplicacionId INTEGER NOT NULL,
            contenidoId INTEGER NOT NULL,
            contenido TEXT NOT NULL,
            fecha TEXT NOT NULL,           -- ISO8601
            link TEXT,
            isRead INTEGER NOT NULL DEFAULT 0,
            UNIQUE(empId, tipoId, comunidadId, aplicacionId, contenidoId) ON CONFLICT REPLACE
          );
        ''');
        await db.execute('CREATE INDEX idx_events_read ON events(isRead);');
        await db.execute(
            'CREATE INDEX idx_events_keys ON events(empId, tipoId, comunidadId, aplicacionId);');
      },
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError(
          'EventSqliteService no inicializado. Llama init() primero.');
    }
    return db;
  }

  /// Inserta SOLO los no existentes desde response['Nivel5'].
  /// Si el evento ya está, NO se actualiza nada (se preserva isRead y demás columnas).
  Future<void> upsertFromNivel5(List<dynamic> nivel5) async {
    if (nivel5.isEmpty) return;
    final db = _database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final raw in nivel5.cast<Map<String, dynamic>>()) {
        batch.insert(
          'events',
          {
            'empId': raw['EmpId'],
            'tipoId': raw['TipoId'],
            'comunidadId': raw['ComunidadId'],
            'aplicacionId': raw['AplicacionId'],
            'contenidoId': raw['ContenidoId'],
            'contenido': (raw['Contenido'] ?? '').toString(),
            'fecha': (raw['Fecha'] ?? '').toString(), // ISO
            'link': raw['Link'],
            'isRead': (raw['isRead'] ?? false) ? 1 : 0,
          },
          // IGNORE => si ya existe por la UNIQUE key, no hace nada.
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  /// Inserta SOLO si no existe (no modifica filas existentes).
  Future<void> upsertOne({
    required int empId,
    required int tipoId,
    required int comunidadId,
    required int aplicacionId,
    required int contenidoId,
    required String contenido,
    required DateTime fecha,
    String? link,
    bool isRead = false,
  }) async {
    await _database.insert(
      'events',
      {
        'empId': empId,
        'tipoId': tipoId,
        'comunidadId': comunidadId,
        'aplicacionId': aplicacionId,
        'contenidoId': contenidoId,
        'contenido': contenido,
        'fecha': fecha.toIso8601String(),
        'link': link,
        'isRead': isRead ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // no pisa existentes
    );
  }

  // Marcar leído / no leído por clave única
  Future<int> setReadByIds({
    required int empId,
    required int tipoId,
    required int comunidadId,
    required int aplicacionId,
    required int contenidoId,
    required bool isRead,
  }) {
    return _database.update(
      'events',
      {'isRead': isRead ? 1 : 0},
      where:
          'empId = ? AND tipoId = ? AND comunidadId = ? AND aplicacionId = ? AND contenidoId = ?',
      whereArgs: [empId, tipoId, comunidadId, aplicacionId, contenidoId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // Obtener eventos con filtros opcionales
  Future<List<Map<String, dynamic>>> getAll({
    int? empId,
    int? tipoId,
    int? comunidadId,
    int? aplicacionId,
    bool? isRead,
    int? limit,
    int? offset,
    String? orderBy, // p.ej. 'fecha DESC'
  }) async {
    final db = _database;
    final where = <String>[];
    final args = <Object?>[];

    void add(String clause, Object? val) {
      where.add(clause);
      args.add(val);
    }

    if (empId != null) add('empId = ?', empId);
    if (tipoId != null) add('tipoId = ?', tipoId);
    if (comunidadId != null) add('comunidadId = ?', comunidadId);
    if (aplicacionId != null) add('aplicacionId = ?', aplicacionId);
    if (isRead != null) add('isRead = ?', isRead ? 1 : 0);

    final rows = await db.query(
      'events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: orderBy ?? 'fecha DESC',
      limit: limit,
      offset: offset,
    );
    return rows;
  }

  // Contar no leídos (con filtros)
  Future<int> countUnread({
    int? empId,
    int? tipoId,
    int? comunidadId,
    int? aplicacionId,
  }) async {
    final db = _database;
    final where = <String>['isRead = 0'];
    final args = <Object?>[];

    if (empId != null) {
      where.add('empId = ?');
      args.add(empId);
    }
    if (tipoId != null) {
      where.add('tipoId = ?');
      args.add(tipoId);
    }
    if (comunidadId != null) {
      where.add('comunidadId = ?');
      args.add(comunidadId);
    }
    if (aplicacionId != null) {
      where.add('aplicacionId = ?');
      args.add(aplicacionId);
    }

    final res = await db.rawQuery(
      'SELECT COUNT(*) c FROM events WHERE ${where.join(' AND ')}',
      args,
    );
    return Sqflite.firstIntValue(res) ?? 0;
  }

  // Borrar todo
  Future<void> clearAll() async => _database.delete('events');

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<List<Map<String, dynamic>>> countUnreadGrouped() async {
    final db = _database;
    final res = await db.rawQuery('''
      SELECT 
        empId, 
        tipoId, 
        comunidadId AS conceptoId,
        COUNT(*) as totalNoLeidos
      FROM events
      WHERE isRead = 0
      GROUP BY empId, tipoId, comunidadId
      ORDER BY empId, tipoId, comunidadId;
    ''');
    return res;
  }

  Future<int> markAllReadForConcept({
    required int empId,
    required int tipoId,
    required int comunidadId, // = conceptoId
  }) async {
    return _database.update(
      'events',
      {'isRead': 1},
      where: 'empId = ? AND tipoId = ? AND comunidadId = ? AND isRead = 0',
      whereArgs: [empId, tipoId, comunidadId],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
