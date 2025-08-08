import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class EncryptionService {
  final String passPhrase;
  final String saltValue;
  final String initVector;

  EncryptionService({
    required this.passPhrase,
    required this.saltValue,
    required this.initVector,
  });

  String encryptAES(String plainText) {
    // Derivar la clave con HMAC-SHA1 y las mismas iteraciones
    final keyBytes = _deriveKey(passPhrase, saltValue, 256 ~/ 8, 2);
    final ivBytes = Uint8List.fromList(utf8.encode(initVector));

    final key = encrypt.Key(keyBytes);
    final iv = encrypt.IV(ivBytes);

    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  String decryptAES(String cipherText) {
    final keyBytes = _deriveKey(passPhrase, saltValue, 256 ~/ 8, 2);
    final ivBytes = Uint8List.fromList(utf8.encode(initVector));

    final key = encrypt.Key(keyBytes);
    final iv = encrypt.IV(ivBytes);

    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    try {
      // Limpia cualquier carácter inválido del texto cifrado
      String cleanCipherText = cipherText.replaceAll(RegExp(r'[^\w+/=]'), '');

      // Desencripta el texto limpio
      final decrypted = encrypter.decrypt64(cleanCipherText, iv: iv);
      return decrypted;
    } catch (e) {
      print("Error al desencriptar: $e");
      rethrow;
    }
  }

  Uint8List _deriveKey(
      String passPhrase, String saltValue, int keyLength, int iterations) {
    final passBytes = utf8.encode(passPhrase);
    final saltBytes = utf8.encode(saltValue);

    final pbkdf2 = _pbkdf2HmacSha1(passBytes, saltBytes, iterations, keyLength);
    return Uint8List.fromList(pbkdf2);
  }

  // Implementación de PBKDF2 con HMAC-SHA1 (para que coincida con C#)
  List<int> _pbkdf2HmacSha1(
      List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha1, password);
    List<int> derivedKey = [];
    int blockCount = (keyLength / hmac.convert([]).bytes.length).ceil();

    for (int block = 1; block <= blockCount; block++) {
      List<int> lastBlock = hmac.convert(salt + [0, 0, 0, block]).bytes;
      List<int> currentBlock = List<int>.from(lastBlock);

      for (int i = 1; i < iterations; i++) {
        lastBlock = hmac.convert(lastBlock).bytes;
        for (int j = 0; j < currentBlock.length; j++) {
          currentBlock[j] ^= lastBlock[j];
        }
      }

      derivedKey.addAll(currentBlock);
    }

    return derivedKey.sublist(0, keyLength);
  }
}
