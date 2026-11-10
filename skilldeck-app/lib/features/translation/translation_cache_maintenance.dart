import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

/// Keeps disk cleanup out of the list's cache-read path.
final translationCacheMaintenanceProvider =
    Provider<TranslationCacheMaintenance>((ref) {
      final maintenance = TranslationCacheMaintenance(
        repository: ref.read(appTranslationRepositoryProvider),
        failureReporter: ref.read(appFailureReporterProvider),
      );
      ref.listen(workspaceSnapshotProvider, (_, next) {
        if (next case AsyncData(value: final snapshot)) {
          maintenance.accept(snapshot);
        }
      });
      if (ref.read(workspaceSnapshotProvider) case AsyncData(
        value: final snapshot,
      )) {
        maintenance.accept(snapshot);
      }
      ref.onDispose(maintenance.dispose);
      return maintenance;
    });

final class TranslationCacheMaintenance {
  TranslationCacheMaintenance({
    required AppTranslationRepository repository,
    required AppFailureReporter failureReporter,
  }) : _repository = repository,
       _failureReporter = failureReporter;

  final AppTranslationRepository _repository;
  final AppFailureReporter _failureReporter;
  final Set<String> _pending = {};
  Map<String, String> _currentHashes = const {};
  bool _running = false;
  bool _disposed = false;

  void accept(SkillsWorkspaceSnapshot snapshot) {
    if (_disposed) return;
    final previous = _currentHashes;
    final next = {
      for (final skill in snapshot.skills)
        skill.slotKey: skill.currentRevision.contentHash,
    };
    for (final entry in next.entries) {
      if (previous[entry.key] != entry.value) _pending.add(entry.key);
    }
    _currentHashes = next;
    if (_pending.isNotEmpty && !_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    final failed = <String>{};
    try {
      while (!_disposed && _pending.isNotEmpty) {
        // Leave a frame between startup slots so list reads can enter the
        // cache's serialized file-lock queue.
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (_disposed || _pending.isEmpty) break;
        final slotKey = _pending.first;
        _pending.remove(slotKey);
        final hash = _currentHashes[slotKey];
        if (hash == null) continue;
        try {
          await _repository.evictStale(
            slotKey: slotKey,
            currentContentHash: hash,
          );
        } on Object catch (error, stackTrace) {
          failed.add(slotKey);
          _failureReporter.capture(
            error,
            stackTrace,
            operationKey: 'evictStaleTranslationCache',
            message: AppFailureMessage.io,
            recoveryPolicy: AppRecoveryPolicy.none,
          );
        }
      }
    } finally {
      _pending.addAll(failed);
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
  }
}
