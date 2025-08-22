import 'dart:convert';
import 'package:http/http.dart' as http;
import 'event_sqlite_service.dart';
import 'storage_service.dart';
import 'config_service.dart';
import '../services/encryption_service.dart';

/// Excepción específica para 401
class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = '401 Unauthorized']);
  @override
  String toString() => 'UnauthorizedException: $message';
}

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

 
  Future<Map<String, dynamic>> fetchData2(String username) async {
    // final apiUrl = ConfigService.apiUrlEventos2;
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
        {'UserCod': encryptedUsername, 'UltimaConexionApp': lastConnection},
      ),
    );

    if (response.statusCode == 200) {
      final dataEncrypt = _encryptionService.decryptAES(response.body);
      final data = json.decode(dataEncrypt) as Map<String, dynamic>;

      final evDb = EventSqliteService();
      await evDb.init();

      // Nivel5: upsert a SQLite
      final nivel5 = (data['Nivel5'] as List?) ?? [];
      await evDb.upsertFromNivel5(nivel5);

      // Construir índice (Empresas -> Tipos -> Conceptos -> Aplicaciones)
      final empresaIndex = buildEmpresaIndex(data);

      // Inyectar conteos de no leídos en cada concepto
      final cantNoLeidos = await evDb.countUnreadGrouped();
      for (final g in cantNoLeidos) {
        final empId = g['empId']?.toString();
        final tipoId = g['tipoId']?.toString();
        final conceptoId = g['conceptoId']?.toString();
        final total = (g['totalNoLeidos'] as int?) ?? 0;

        if (empId == null || tipoId == null || conceptoId == null) continue;

        final empresa = empresaIndex[empId] as Map<String, dynamic>?;
        if (empresa == null) continue;

        final tipos = empresa['tipos'] as Map<String, dynamic>?;
        final tipo = tipos?[tipoId] as Map<String, dynamic>?;
        if (tipo == null) continue;

        final conceptos = tipo['conceptos'] as Map<String, dynamic>?;
        final concepto = conceptos?[conceptoId] as Map<String, dynamic>?;
        if (concepto == null) continue;

        concepto['totalNoLeidos'] = total;
      }

      // Actualizar "última conexión"
      final newSession =
          session?.copyWith(lastEventFetch: DateTime.now().toString());
      if (newSession != null) {
        await storageService.saveSession(newSession);
      }

      return empresaIndex;
    } else if (response.statusCode == 401) {
      throw UnauthorizedException();
    } else {
      throw Exception('Error al obtener los datos: ${response.statusCode}');
    }
  }

  Future<void> clearLocalData() async {
    await storageService.saveEvents({});
  }

  /// Lee un valor (id) desde varias posibles claves (camelCase/snake_case), y lo retorna como string.
  String _idStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  /// Construye la estructura:
  /// empresa[empId]["tipos"][tipoId]["conceptos"][conceptoId].aplicaciones[appId]
  /// Compatibilidad con claves camelCase y snake_case:
  /// - EmpId / empresa_id
  /// - TipoId / tipo_id
  /// - ConceptoId / concepto_id
  /// - AplicacionId / aplicacion_id
  ///
  /// IMPORTANTE: Nivel 3 y 4 se insertan usando **EmpId** (filtrado por empresa).
  Map<String, dynamic> buildEmpresaIndex(Map<String, dynamic> response) {
    final Map<String, dynamic> empresa = {};

    // Nivel1: Empresas
    for (final e in List<Map<String, dynamic>>.from(response['Nivel1'] ?? [])) {
      final empId = _idStr(e, ['EmpId', 'empresa_id', 'emp_id']);
      if (empId.isEmpty) continue;

      empresa[empId] = {
        'EmpId': e['EmpId'] ?? e['empresa_id'] ?? e['emp_id'],
        'Empresa': e['Empresa'] ?? e['empresa'],
        'LogoEmp': e['LogoEmp'] ?? e['logo_emp'],
        'tipos': <String, dynamic>{},
      };
    }

    // Nivel2: Tipos (por empresa)
    for (final t in List<Map<String, dynamic>>.from(response['Nivel2'] ?? [])) {
      final empId = _idStr(t, ['EmpId', 'empresa_id', 'emp_id']);
      final tipoId = _idStr(t, ['TipoId', 'tipo_id']);
      if (empId.isEmpty || tipoId.isEmpty) continue;

      empresa.putIfAbsent(empId, () {
        return {
          'EmpId': t['EmpId'] ?? t['empresa_id'] ?? t['emp_id'],
          'Empresa': null,
          'LogoEmp': null,
          'tipos': <String, dynamic>{},
        };
      });

      final tipos = empresa[empId]['tipos'] as Map<String, dynamic>;
      tipos[tipoId] = {
        'EmpId': t['EmpId'] ?? t['empresa_id'] ?? t['emp_id'],
        'TipoId': t['TipoId'] ?? t['tipo_id'],
        'Tipo': t['Tipo'] ?? t['tipo'],
        'Logo': t['Logo'] ?? t['logo'],
        'conceptos': <String, dynamic>{},
      };
    }

    // Nivel3: Conceptos (por empresa + tipo)
    // AHORA VIENEN con EmpId / empresa_id → insertamos SOLO en la empresa/tipo correspondiente
    for (final c in List<Map<String, dynamic>>.from(response['Nivel3'] ?? [])) {
      final empId = _idStr(c, ['EmpId', 'empresa_id', 'emp_id']);
      final tipoId = _idStr(c, ['TipoId', 'tipo_id']);
      final conceptoId = _idStr(c, ['ConceptoId', 'concepto_id']);
      if (empId.isEmpty || tipoId.isEmpty || conceptoId.isEmpty) continue;

      final empData = empresa[empId] as Map<String, dynamic>?;
      if (empData == null) continue;

      final tipos = empData['tipos'] as Map<String, dynamic>?;
      final tipoData = tipos?[tipoId] as Map<String, dynamic>?;
      if (tipoData == null) continue;

      final conceptos = tipoData['conceptos'] as Map<String, dynamic>;
      conceptos[conceptoId] = {
        'EmpId': c['EmpId'] ?? c['empresa_id'] ?? c['emp_id'],
        'TipoId': c['TipoId'] ?? c['tipo_id'],
        'ConceptoId': c['ConceptoId'] ?? c['concepto_id'],
        'Concepto': c['Concepto'] ?? c['concepto'],
        'UrlIcoConcepto': c['UrlIcoConcepto'] ?? c['url_ico_concepto'],
        'UrlConcepto': c['UrlConcepto'] ?? c['url_concepto'],
        'aplicaciones': <String, dynamic>{},
        'totalNoLeidos': 0,
      };
    }

    // Nivel4: Aplicaciones (por empresa + tipo + concepto)
    for (final a in List<Map<String, dynamic>>.from(response['Nivel4'] ?? [])) {
      final empId = _idStr(a, ['EmpId', 'empresa_id', 'emp_id']);
      final tipoId = _idStr(a, ['TipoId', 'tipo_id']);
      final conceptoId = _idStr(a, ['ConceptoId', 'concepto_id']);
      final appId = _idStr(a, ['AplicacionId', 'aplicacion_id']);
      if (empId.isEmpty || tipoId.isEmpty || conceptoId.isEmpty || appId.isEmpty) {
        continue;
      }

      final empData = empresa[empId] as Map<String, dynamic>?;
      if (empData == null) continue;

      final tipos = empData['tipos'] as Map<String, dynamic>?;
      final tipoData = tipos?[tipoId] as Map<String, dynamic>?;
      if (tipoData == null) continue;

      final conceptos = tipoData['conceptos'] as Map<String, dynamic>?;
      final conceptoData = conceptos?[conceptoId] as Map<String, dynamic>?;
      if (conceptoData == null) continue;

      final apps = conceptoData['aplicaciones'] as Map<String, dynamic>;
      apps[appId] = {
        'EmpId': a['EmpId'] ?? a['empresa_id'] ?? a['emp_id'],
        'TipoId': a['TipoId'] ?? a['tipo_id'],
        'ConceptoId': a['ConceptoId'] ?? a['concepto_id'],
        'AplicacionId': a['AplicacionId'] ?? a['aplicacion_id'],
        'Aplicacion': a['Aplicacion'] ?? a['aplicacion'],
        'UrlIcoAplicacion': a['UrlIcoAplicacion'] ?? a['url_ico_aplicacion'],
      };
    }

    return empresa;

    // Estructura final:
    // {
    //   "12": {
    //     EmpId, Empresa, LogoEmp,
    //     "tipos": {
    //       "1": {
    //         EmpId, TipoId, Tipo, Logo,
    //         "conceptos": {
    //           "12": {
    //             EmpId, TipoId, ConceptoId, Concepto, UrlIcoConcepto, UrlConcepto,
    //             "aplicaciones": {
    //               "1": { EmpId, TipoId, ConceptoId, AplicacionId, Aplicacion, UrlIcoAplicacion }
    //             },
    //             totalNoLeidos
    //           }
    //         }
    //       }
    //     }
    //   },
    //   "_UltimaConexiones": [ ... ]
    // }
  }

  /// Retorna eventos de un concepto, ordenados:
  /// 1) No leídos por fecha DESC, luego 2) Leídos por fecha DESC.
  Future<List<Map<String, dynamic>>> getEventsByConcept({
    required int empId,
    required int tipoId,
    required int conceptoId, // corresponde a comunidadId en SQLite
  }) async {
    final evDb = EventSqliteService();
    await evDb.init();

    final unread = await evDb.getAll(
      empId: empId,
      tipoId: tipoId,
      comunidadId: conceptoId,
      isRead: false,
      orderBy: 'fecha DESC',
    );

    final read = await evDb.getAll(
      empId: empId,
      tipoId: tipoId,
      comunidadId: conceptoId,
      isRead: true,
      orderBy: 'fecha DESC',
    );

    return [...unread, ...read];
  }

  /// Marca como leídos todos los eventos del concepto
  Future<int> markConceptEventsRead({
    required int empId,
    required int tipoId,
    required int conceptoId,
  }) async {
    final evDb = EventSqliteService();
    await evDb.init();
    return evDb.markAllReadForConcept(
      empId: empId,
      tipoId: tipoId,
      comunidadId: conceptoId,
    );
  }

  /// Total no leídos del concepto (para refrescar Home)
  Future<int> getUnreadCountForConcept({
    required int empId,
    required int tipoId,
    required int conceptoId,
  }) async {
    final evDb = EventSqliteService();
    await evDb.init();
    return evDb.countUnread(
      empId: empId,
      tipoId: tipoId,
      comunidadId: conceptoId,
    );
  }
}
