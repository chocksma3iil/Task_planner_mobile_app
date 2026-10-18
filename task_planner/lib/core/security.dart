import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Password hashing for local accounts.
///
/// Stores `salt:hash` where hash is SHA-256 over salt + password.
/// Pure Dart so it stays unit-testable without a device or database.
class PasswordHasher {
  static const _separator = ':';

  /// Hashes [password] with a fresh random salt.
  static String hash(String password) {
    final salt = _makeSalt();
    return '$salt$_separator${_digest(salt, password)}';
  }

  /// Returns true when [password] matches the stored `salt:hash` value.
  /// Returns false for malformed stored values instead of throwing.
  static bool verify(String password, String stored) {
    final parts = stored.split(_separator);
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return false;
    }
    return _digest(parts[0], password) == parts[1];
  }

  static String _makeSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _digest(String salt, String password) {
    return sha256.convert(utf8.encode('$salt$password')).toString();
  }
}
