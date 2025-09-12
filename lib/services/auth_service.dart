import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_service.dart';
import '../services/config_service.dart';
import '../models/session.dart';
import '../services/encryption_service.dart';
import 'data_service.dart';

class AuthService {
  static const String _encPasswordKey = 'enc_password_v1';

  final StorageService _storageService = StorageService();
  final DataService _dataService;
  late final EncryptionService _encryptionService;

  AuthService(this._dataService) {
    _encryptionService = EncryptionService(
      passPhrase: ConfigService.secPassPhraseApi ?? '',
      saltValue: ConfigService.secSaltValueApi ?? '',
      initVector: ConfigService.secInitVectorApi ?? '',
    );
  }

  /// Login normal: encripta credenciales, pega al endpoint, guarda Session
  /// y persiste la CONTRASEÑA *ya encriptada* para reautenticación silenciosa.
  Future<bool> login(String username, String password) async {
    final Session? currentSession = await _storageService.getSession();

    if (currentSession == null ||
        currentSession.username != username ||
        !currentSession.isLoggedIn) {
      await _dataService.clearLocalData();
      await _storageService.removeSession();
    }

    final ok = await _obtainTokenAndSaveSession(username, password);
    if (ok) {
      // Guardamos también la contraseña ENCRIPTADA para reauth futura
      final encPassword = _encryptionService.encryptAES(password);
      await _saveEncryptedPassword(encPassword);
    }
    return ok;
  }

  /// Usado internamente y por DataService para reautenticación silenciosa:
  /// recibe el password YA encriptado y lo envía tal cual al backend.
  Future<bool> loginWithEncryptedPassword({
    required String username,
    required String encryptedPassword,
  }) async {
    final apiUrlLogin = ConfigService.apiUrlLogin;
    if (apiUrlLogin == null) {
      throw Exception('URL de login no está configurada.');
    }

    // El backend espera ambos valores encriptados.
    final encUsername = _encryptionService.encryptAES(username);

    final response = await http.post(
      Uri.parse(apiUrlLogin),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'Username': encUsername,
        'Password': encryptedPassword, // ya encriptado
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = json.decode(response.body);
      final token = responseData['Token'] ?? '';

      if (token.isNotEmpty) {
        final nowMillis = DateTime.now().millisecondsSinceEpoch;
        final old = await _storageService.getSession();
        final session = Session(
          token: token,
          username: username,
          loginTime: nowMillis,
          lastEventFetch: old?.lastEventFetch,
          isLoggedIn: true,
        );
        await _storageService.saveSession(session);
        return true;
      }
    } else if (response.statusCode == 401) {
      // credenciales inválidas — probablemente cambiaron la clave
      return false;
    }

    return false;
  }

  Future<bool> _obtainTokenAndSaveSession(
      String username, String password) async {
    final apiUrlLogin = ConfigService.apiUrlLogin;

    if (apiUrlLogin == null) {
      throw Exception('URL de login no está configurada.');
    }

    final encryptedUsername = _encryptionService.encryptAES(username);
    final encryptedPassword = _encryptionService.encryptAES(password);

    final response = await http.post(
      Uri.parse(apiUrlLogin),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'Username': encryptedUsername,
        'Password': encryptedPassword,
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = json.decode(response.body);
      final token = responseData['Token'] ?? '';

      if (token.isNotEmpty) {
        final loginTime = DateTime.now().millisecondsSinceEpoch;
        final session = Session(
          token: token,
          username: username,
          loginTime: loginTime,
          isLoggedIn: true,
          lastEventFetch: (await _storageService.getSession())?.lastEventFetch,
        );
        await _storageService.saveSession(session);
        return true;
      }
    } else if (response.statusCode == 401) {
      throw Exception('Usuario o contraseña incorrectos');
    }

    return false;
  }

  /// Intenta reautenticarse usando la contraseña encriptada guardada.
  /// Retorna true si pudo renovar token; false si no hay password guardada o falló login.
  Future<bool> reauthenticateIfPossible() async {
    final session = await _storageService.getSession();
    if (session == null || session.username.isEmpty) return false;

    final encPass = await _getEncryptedPassword();
    if (encPass == null || encPass.isEmpty) return false;

    return loginWithEncryptedPassword(
      username: session.username,
      encryptedPassword: encPass,
    );
  }

  Future<bool> isSessionValid(Session session) async {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final sessionDurationMinutes = (currentTime - session.loginTime) / 60000;

    if (sessionDurationMinutes >= ConfigService.sessionMaxLifetimeMinutes) {
      final updatedSession = session.copyWith(isLoggedIn: false);
      await _storageService.saveSession(updatedSession);
      return false;
    }

    return true;
  }

  Future<Session?> getSession() async {
    return await _storageService.getSession();
  }

  Future<void> logout() async {
    final session = await _storageService.getSession();
    if (session != null) {
      final updatedSession = session.copyWith(isLoggedIn: false);
      await _storageService.saveSession(updatedSession);
    }
    await _clearEncryptedPassword();
  }

  // ======= helpers para contraseña encriptada (guardada tal cual) =======

  Future<void> _saveEncryptedPassword(String enc) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_encPasswordKey, enc);
  }

  Future<String?> _getEncryptedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_encPasswordKey);
  }

  Future<void> _clearEncryptedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_encPasswordKey);
  }
}
