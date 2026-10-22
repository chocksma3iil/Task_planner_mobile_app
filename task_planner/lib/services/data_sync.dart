import 'dart:async';

/// Signals "server data changed" after a successful mutation so list streams
/// refetch. Services ping after writes; [watchFromApi] re-runs its fetch on
/// every ping, which keeps screens updating without provider rebuilds (and
/// therefore without loading-spinner flicker).
class DataSync {
  DataSync._();

  static final DataSync instance = DataSync._();

  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void ping() => _changes.add(null);
}

/// Emits [fetch]'s result immediately, then again after every [DataSync]
/// ping. A failed fetch errors the stream; screens recover through their
/// existing retry actions (provider invalidation resubscribes).
Stream<T> watchFromApi<T>(Future<T> Function() fetch) async* {
  yield await fetch();
  await for (final _ in DataSync.instance.changes) {
    yield await fetch();
  }
}
