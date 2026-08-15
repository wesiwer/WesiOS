import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

class WesiAiBackupCrypto {
  static const int _saltBytes = 16;
  static const int _nonceBytes = 12;
  static const int _keyBytes = 32;
  static const int _pbkdf2Iterations = 150000;
  static const String _backupMagic = 'WAB1';
  static const String _transferMagic = 'WAT1';

  const WesiAiBackupCrypto._();

  static Uint8List randomSessionKey() => _randomBytes(_keyBytes);

  static Uint8List encryptBackup(
    Uint8List plain,
    String passphrase,
  ) {
    final normalized = passphrase.trim();
    if (normalized.length < 8 || normalized.length > 512) {
      throw const FormatException(
          'Пароль backup должен содержать минимум 8 символов');
    }
    final salt = _randomBytes(_saltBytes);
    final key = _deriveKey(normalized, salt);
    final nonce = _randomBytes(_nonceBytes);
    final magic = Uint8List.fromList(ascii.encode(_backupMagic));
    final cipher = _crypt(
      plain: plain,
      key: key,
      nonce: nonce,
      aad: magic,
      encrypt: true,
    );
    return Uint8List.fromList(<int>[...magic, ...salt, ...nonce, ...cipher]);
  }

  static Uint8List decryptBackup(
    Uint8List encoded,
    String passphrase,
  ) {
    final minLength = 4 + _saltBytes + _nonceBytes + 16;
    if (encoded.lengthInBytes < minLength) {
      throw const FormatException('Повреждённый Wesi AI backup');
    }
    final magic = Uint8List.sublistView(encoded, 0, 4);
    if (ascii.decode(magic) != _backupMagic) {
      throw const FormatException('Это не Wesi AI backup');
    }
    final salt = Uint8List.sublistView(encoded, 4, 4 + _saltBytes);
    final nonce = Uint8List.sublistView(
      encoded,
      4 + _saltBytes,
      4 + _saltBytes + _nonceBytes,
    );
    final body = Uint8List.sublistView(
      encoded,
      4 + _saltBytes + _nonceBytes,
    );
    try {
      return _crypt(
        plain: body,
        key: _deriveKey(passphrase.trim(), Uint8List.fromList(salt)),
        nonce: Uint8List.fromList(nonce),
        aad: Uint8List.fromList(magic),
        encrypt: false,
      );
    } catch (_) {
      throw const FormatException('Неверный пароль или backup повреждён');
    }
  }

  static Uint8List encryptTransfer(
    Uint8List plain,
    Uint8List key,
  ) {
    _validateSessionKey(key);
    final magic = Uint8List.fromList(ascii.encode(_transferMagic));
    final nonce = _randomBytes(_nonceBytes);
    final cipher = _crypt(
      plain: plain,
      key: key,
      nonce: nonce,
      aad: magic,
      encrypt: true,
    );
    return Uint8List.fromList(<int>[...magic, ...nonce, ...cipher]);
  }

  static Uint8List decryptTransfer(
    Uint8List encoded,
    Uint8List key,
  ) {
    _validateSessionKey(key);
    if (encoded.lengthInBytes < 4 + _nonceBytes + 16) {
      throw const FormatException('Повреждённый D2D пакет Wesi AI');
    }
    final magic = Uint8List.sublistView(encoded, 0, 4);
    if (ascii.decode(magic) != _transferMagic) {
      throw const FormatException('Некорректный D2D пакет Wesi AI');
    }
    final nonce = Uint8List.sublistView(encoded, 4, 4 + _nonceBytes);
    final body = Uint8List.sublistView(encoded, 4 + _nonceBytes);
    try {
      return _crypt(
        plain: body,
        key: key,
        nonce: Uint8List.fromList(nonce),
        aad: Uint8List.fromList(magic),
        encrypt: false,
      );
    } catch (_) {
      throw const FormatException('D2D пакет не прошёл проверку целостности');
    }
  }

  static String fingerprint(Uint8List key) {
    _validateSessionKey(key);
    final digest = crypto.sha256.convert(key).toString().toUpperCase();
    return '${digest.substring(0, 4)}-${digest.substring(4, 8)}-${digest.substring(8, 12)}';
  }

  static String transferAuthToken(
    String sessionId,
    Uint8List key,
  ) {
    _validateSessionKey(key);
    final hmac = crypto.Hmac(crypto.sha256, key);
    return hmac.convert(utf8.encode('wesi-ai-d2d:$sessionId')).toString();
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static Uint8List _deriveKey(String passphrase, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyBytes));
    return derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
  }

  static Uint8List _crypt({
    required Uint8List plain,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required bool encrypt,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          nonce,
          aad,
        ),
      );
    return cipher.process(plain);
  }

  static Uint8List _randomBytes(int count) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(count, (_) => random.nextInt(256)),
    );
  }

  static void _validateSessionKey(Uint8List key) {
    if (key.lengthInBytes != _keyBytes) {
      throw const FormatException('Некорректный D2D session key');
    }
  }
}
