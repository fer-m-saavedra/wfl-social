import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';
import '../services/config_service.dart';
import '../models/session.dart';
import '../services/encryption_service.dart';
import 'data_service.dart';

class AuthService {
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

  Future<bool> login(String username, String password) async {
    final Session? currentSession = await _storageService.getSession();

    if (currentSession == null ||
        currentSession.username != username ||
        !currentSession.isLoggedIn) {
      await _dataService.clearLocalData();
      await _storageService.removeSession();
      return await _obtainTokenAndSaveSession(username, password);
    }

    return await _obtainTokenAndSaveSession(username, password);
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
        );
        await _storageService.saveSession(session);
        return true;
      }
    } else if (response.statusCode == 401) {
      throw Exception('Usuario o contraseña incorrectos');
    }

    return false;
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
  }
}
