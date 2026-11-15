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
///
/// Implemented with an explicit [StreamController] instead of an `async*`
/// generator: cancelling an `async*` stream that is waiting on a broadcast
/// stream never completes, which leaks subscriptions and hangs provider
/// disposal.
Stream<T> watchFromApi<T>(Future<T> Function() fetch) {
  late final StreamController<T> controller;
  StreamSubscription<void>? changes;
  var cancelled = false;
  var fetching = false;
  var queued = false;

  Future<void> refresh() async {
    if (fetching) {
      queued = true;
      return;
    }
    fetching = true;
    do {
      queued = false;
      try {
        final value = await fetch();
        if (!cancelled) {
          controller.add(value);
        }
      } catch (error, stackTrace) {
        if (!cancelled) {
          controller.addError(error, stackTrace);
        }
        queued = false;
      }
    } while (queued && !cancelled);
    fetching = false;
  }

  controller = StreamController<T>(
    onListen: () {
      changes = DataSync.instance.changes.listen((_) => refresh());
      refresh();
    },
    onCancel: () async {
      cancelled = true;
      await changes?.cancel();
      changes = null;
    },
  );
  return controller.stream;
}
