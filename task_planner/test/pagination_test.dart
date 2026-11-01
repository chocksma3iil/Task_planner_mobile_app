import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/providers/data_providers.dart';

/// Twelve rows served five at a time. The second and third pages repeat the
/// previous page's last row, so the test proves deduplication as well.
class _PagedInts extends PaginatedNotifier<int> {
  int fetchCount = 0;

  @override
  int get pageSize => 5;

  @override
  Object keyOf(int item) => item;

  @override
  Future<PageResult<int>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    fetchCount++;
    const all = 12;
    final start = offset == 0 ? 0 : offset - 1;
    final items = <int>[
      for (var i = start; i < all && i < start + limit; i++) i + 1,
    ];
    return PageResult(items: items, total: all);
  }
}

void main() {
  final provider =
      AsyncNotifierProvider<_PagedInts, PaginatedList<int>>(_PagedInts.new);

  Future<ProviderContainer> boot() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    return container;
  }

  test('first page loads alone', () async {
    final container = await boot();
    final state = container.read(provider).value!;
    expect(state.items, [1, 2, 3, 4, 5]);
    expect(state.page, 1);
    expect(state.hasMore, isTrue);
    expect(container.read(provider.notifier).fetchCount, 1);
  });

  test('loadMore appends pages, drops duplicates, and stops at the total',
      () async {
    final container = await boot();
    final notifier = container.read(provider.notifier);

    await notifier.loadMore();
    var state = container.read(provider).value!;
    expect(state.items, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(state.page, 2);
    expect(state.hasMore, isTrue);

    await notifier.loadMore();
    state = container.read(provider).value!;
    expect(state.items, List<int>.generate(12, (i) => i + 1));
    expect(state.page, 3);
    expect(state.hasMore, isFalse);

    // No request once the last page is known.
    final calls = notifier.fetchCount;
    await notifier.loadMore();
    expect(notifier.fetchCount, calls);
  });

  test('concurrent loadMore calls only fetch one page', () async {
    final container = await boot();
    final notifier = container.read(provider.notifier);

    await Future.wait([notifier.loadMore(), notifier.loadMore()]);
    expect(notifier.fetchCount, 2);
    expect(
      container.read(provider).value!.items,
      [1, 2, 3, 4, 5, 6, 7, 8, 9],
    );
  });

  test('refresh reloads page one and discards later pages', () async {
    final container = await boot();
    final notifier = container.read(provider.notifier);
    await notifier.loadMore();
    expect(container.read(provider).value!.items.length, 9);

    await notifier.refresh();
    final state = container.read(provider).value!;
    expect(state.items, [1, 2, 3, 4, 5]);
    expect(state.page, 1);
    expect(state.hasMore, isTrue);
  });
}
