import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'event_sqlite_service.dart';
import 'storage_service.dart';
import 'config_service.dart';
import '../services/encryption_service.dart';

/// Excepción específica para 401 (cuando falla la reautenticación silenciosa).
class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException([this.message = '401 Unauthorized']);
  @override
  String toString() => 'UnauthorizedException: $message';
}

class DataService {
  static const String _encPasswordKey = 'enc_password_v1';

  final StorageService storageService;
  late final EncryptionService _encryptionService;

  DataService({required this.storageService}) {
    _encryptionService = EncryptionService(
      passPhrase: ConfigService.secPassPhraseApi ?? '',
      saltValue: ConfigService.secSaltValueApi ?? '',
      initVector: ConfigService.secInitVectorApi ?? '',
    );
  }

  /// Fetch principal con reintento automático si el token expiró:
  /// - Si responde 401: intenta reautenticarse con password encriptado guardado.
  /// - Si la reauth funciona: guarda nuevo token en Session y vuelve a intentar el fetch UNA vez.
  /// - Si la reauth falla: lanza UnauthorizedException → la UI decide ir a Login.
  Future<Map<String, dynamic>> fetchData2(String username) async {
    final result = await _fetchOnce(username);
    if (result.$1) {
      // ok a la primera
      return result.$2;
    }

    // Si no ok: ver si fue 401 y reauth posible
    if (result.$3 == 401) {
      final reauthOk = await _attemptSilentReauth(username);
      if (reauthOk) {
        final retry = await _fetchOnce(username);
        if (retry.$1) return retry.$2;
      }
      // Reauth falló → avisamos a la capa superior
      throw UnauthorizedException();
    }

    // Otra falla diferente a 401
    throw Exception('Error al obtener los datos: ${result.$3}');
  }

  /// Llama al endpoint una vez. Retorna (ok, data, statusCode).
  Future<(bool, Map<String, dynamic>, int)> _fetchOnce(String username) async {
    final apiUrl = ConfigService.apiUrlEventos; // o apiUrlEventos2
    if (apiUrl == null) {
      throw Exception('La URL del servicio de eventos no está configurada.');
    }

    final session = await storageService.getSession();
    final lastConnection =
        session?.lastEventFetch ?? DateTime.now().toString();
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

      // Nivel5 -> SQLite
      final nivel5 = (data['Nivel5'] as List?) ?? [];
      await evDb.upsertFromNivel5(nivel5);

      // Construir índice (Empresas -> Tipos -> Conceptos -> Aplicaciones)
      final empresaIndex = buildEmpresaIndex(data);

      // Inyectar conteos de no leídos
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

      // Actualizar "última conexión" en la sesión
      final newSession = session?.copyWith(
        lastEventFetch: DateTime.now().toString(),
      );
      if (newSession != null) {
        await storageService.saveSession(newSession);
      }

      return (true, empresaIndex, 200);
    }

    // No 200 → devolvemos fallo con status
    return (false, <String, dynamic>{}, response.statusCode);
  }

  /// Reauth silenciosa: usa la contraseña *ya encriptada* en SharedPreferences.
  /// Si funciona, actualiza el token en Session.
  Future<bool> _attemptSilentReauth(String username) async {
    final apiUrlLogin = ConfigService.apiUrlLogin;
    if (apiUrlLogin == null) return false;

    // Recuperar password ENCRIPTADO
    final prefs = await SharedPreferences.getInstance();
    final encPassword = prefs.getString(_encPasswordKey);
    if (encPassword == null || encPassword.isEmpty) return false;

    // Backend espera Username y Password encriptados.
    final encUsername = _encryptionService.encryptAES(username);

    final response = await http.post(
      Uri.parse(apiUrlLogin),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'Username': encUsername,
        'Password': encPassword,
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = json.decode(response.body);
      final token = responseData['Token'] ?? '';
      if (token.isNotEmpty) {
        final old = await storageService.getSession();
        if (old == null) return false;

        final nowMillis = DateTime.now().millisecondsSinceEpoch;
        final updated = old.copyWith(
          token: token,
          isLoggedIn: true,
          loginTime: nowMillis,
        );
        await storageService.saveSession(updated);
        return true;
      }
    }

    return false;
  }

  Future<void> clearLocalData() async {
    await storageService.saveEvents({});
  }

  // ---- Helpers de indexación y APIs locales (iguales a tu versión previa) ----

  String _idStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

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
  }

  /// Eventos por concepto
  Future<List<Map<String, dynamic>>> getEventsByConcept({
    required int empId,
    required int tipoId,
    required int conceptoId,
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
