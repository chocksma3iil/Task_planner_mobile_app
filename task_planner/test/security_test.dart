import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/core/security.dart';

void main() {
  test('hash then verify round-trips', () {
    final stored = PasswordHasher.hash('s3cret!');
    expect(PasswordHasher.verify('s3cret!', stored), isTrue);
  });

  test('wrong password fails', () {
    final stored = PasswordHasher.hash('s3cret!');
    expect(PasswordHasher.verify('other', stored), isFalse);
  });

  test('two hashes of the same password differ (random salt)', () {
    expect(PasswordHasher.hash('same'), isNot(PasswordHasher.hash('same')));
  });

  test('malformed stored values fail closed', () {
    expect(PasswordHasher.verify('x', 'not-a-hash'), isFalse);
    expect(PasswordHasher.verify('x', ''), isFalse);
  });

  test('stored value never contains the plain password', () {
    const password = 's3cret!';
    expect(PasswordHasher.hash(password).contains(password), isFalse);
  });
}
