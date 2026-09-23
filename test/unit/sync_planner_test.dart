import 'package:flutter_test/flutter_test.dart';
import 'package:weather_alerts/services/sync/sync_planner.dart';

DateTime at(int minute) => DateTime.utc(2026, 1, 1, 0, minute);

void main() {
  group('SyncPlanner', () {
    test('uploads a brand-new local record', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(1)},
        remote: const {},
        snapshot: const {},
      );

      expect(plan.uploadKeys, ['a']);
      expect(plan.applyLocalKeys, isEmpty);
      expect(plan.deleteRemoteKeys, isEmpty);
      expect(plan.deleteLocalKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(1)});
    });

    test('applies a brand-new remote record', () {
      final plan = SyncPlanner.plan(
        local: const {},
        remote: {'a': at(1)},
        snapshot: const {},
      );

      expect(plan.applyLocalKeys, ['a']);
      expect(plan.uploadKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(1)});
    });

    test('does nothing when both sides agree', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(1)},
        remote: {'a': at(1)},
        snapshot: const {},
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.nextSnapshot, {'a': at(1)});
    });

    test('uploads when local is newer', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(2)},
        remote: {'a': at(1)},
        snapshot: const {},
      );

      expect(plan.uploadKeys, ['a']);
      expect(plan.applyLocalKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(2)});
    });

    test('applies when remote is newer', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(1)},
        remote: {'a': at(2)},
        snapshot: const {},
      );

      expect(plan.applyLocalKeys, ['a']);
      expect(plan.uploadKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(2)});
    });

    test('propagates a local deletion when the remote copy is unchanged', () {
      final plan = SyncPlanner.plan(
        local: const {},
        remote: {'a': at(1)},
        snapshot: {'a': at(1)},
      );

      expect(plan.deleteRemoteKeys, ['a']);
      expect(plan.applyLocalKeys, isEmpty);
      expect(plan.nextSnapshot, isNot(contains('a')));
    });

    test('propagates a remote deletion when the local copy is unchanged', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(1)},
        remote: const {},
        snapshot: {'a': at(1)},
      );

      expect(plan.deleteLocalKeys, ['a']);
      expect(plan.uploadKeys, isEmpty);
      expect(plan.nextSnapshot, isNot(contains('a')));
    });

    test('remote edit after a local deletion wins', () {
      final plan = SyncPlanner.plan(
        local: const {},
        remote: {'a': at(2)},
        snapshot: {'a': at(1)},
      );

      expect(plan.applyLocalKeys, ['a']);
      expect(plan.deleteRemoteKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(2)});
    });

    test('local edit after a remote deletion wins (re-create)', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(2)},
        remote: const {},
        snapshot: {'a': at(1)},
      );

      expect(plan.uploadKeys, ['a']);
      expect(plan.deleteLocalKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(2)});
    });

    test('drops keys deleted on both sides', () {
      final plan = SyncPlanner.plan(
        local: const {},
        remote: const {},
        snapshot: {'a': at(1)},
      );

      expect(plan.isEmpty, isTrue);
      expect(plan.nextSnapshot, isEmpty);
    });

    test('recreates the cloud copy for append-only domains (deletions off)', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(1)},
        remote: const {},
        snapshot: {'a': at(1)},
        deletionsEnabled: false,
      );

      expect(plan.uploadKeys, ['a']);
      expect(plan.deleteLocalKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(1)});
    });

    test('reapplies locally for append-only domains (deletions off)', () {
      final plan = SyncPlanner.plan(
        local: const {},
        remote: {'a': at(1)},
        snapshot: {'a': at(1)},
        deletionsEnabled: false,
      );

      expect(plan.applyLocalKeys, ['a']);
      expect(plan.deleteRemoteKeys, isEmpty);
      expect(plan.nextSnapshot, {'a': at(1)});
    });

    test('closures: remote-only fresh key is applied and snapshotted', () {
      final plan = SyncPlanner.plan(
        local: {'a': at(1)},
        remote: {'a': at(0), 'b': at(5)},
        snapshot: {'a': at(1)},
      );

      // a is a local edit (l > r), b is brand new remotely.
      expect(plan.uploadKeys, ['a']);
      expect(plan.applyLocalKeys, ['b']);
      expect(plan.nextSnapshot, {'a': at(1), 'b': at(5)});
    });
  });
}