import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/command_host/data/approval_command_handlers.dart';
import 'package:skills_manager/features/command_host/data/command_approval.dart';
import 'package:skills_manager/features/command_host/data/command_approval_registry.dart';
import 'package:skills_manager/features/command_host/data/command_cancellation.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity_reporter.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import 'support/approval_presenter.dart';
import 'support/read_fixtures.dart';
import 'support/write_repository.dart';

void main() {
  void scenario(void Function(_Harness) body) => fakeAsync((time) {
    final harness = _Harness(time);
    try {
      body(harness);
    } finally {
      unawaited(harness.registry.close());
      time.flushMicrotasks();
      harness.container.dispose();
      unawaited(harness.repo.publications.close());
      time.flushMicrotasks();
    }
  });

  test('mixed Sources execute each narrowed input in request order', () {
    scenario((h) {
      const sources = [
        SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://github.com/org/first',
          ref: 'next',
          skillPath: 'skills/alpha',
        ),
        SkillSourceInput(
          kind: WorkspaceSourceKind.git,
          locator: 'https://github.com/org/second',
          repositorySubpath: 'packages',
          skillPath: 'beta',
        ),
      ];
      CommandResult? result;
      unawaited(
        h.registry
            .request(
              command: 'source relink',
              subject: CommandApprovalReplaceSource([
                for (var i = 0; i < sources.length; i++)
                  CommandApprovalReplaceSourceItem(
                    skillId: ['alpha', 'beta'][i],
                    source: sources[i],
                    candidateDeclaredName: ['alpha', 'beta'][i],
                  ),
              ]),
              items: [
                (id: 'alpha', slotKey: 'alpha'),
                (id: 'beta', slotKey: 'beta'),
              ],
              timeout: const Duration(seconds: 90),
            )
            .then((value) => result = value),
      );
      h.time.flushMicrotasks();
      expect(h.repo.replaceSourceRequests, isEmpty);
      h.approve(7);
      expect(result!.ok, true);
      expect(result!.command, 'source relink');
      expect(h.repo.replaceSourceRequests.map((r) => r.skillId.value), [
        'alpha',
        'beta',
      ]);
      expect(h.repo.replaceSourceRequests.map((r) => r.source), sources);
      expect(h.repo.replaceSourceRequests.map((r) => r.expectedRevision), [
        7,
        8,
      ]);
    });
  });

  test(
    'replacement advances only from returned commits, reports after approval',
    () {
      scenario((h) {
        h.repo.candidates = [
          for (final s in h.repo.current.skills)
            WriteRepository.candidate(s.slotKey),
        ];
        final running = h.run('source replace');
        expect(h.repo.calls, ['inspect']);
        expect(h.activity, isNull);
        h.approve(7);
        final result = h.finish(running);
        expect(result.ok, true);
        expect(h.repo.replaceSourceRequests.map((r) => r.skillId.value), [
          'alpha',
          'beta',
          'gamma',
        ]);
        expect(h.repo.replaceSourceRequests.map((r) => r.expectedRevision), [
          7,
          8,
          9,
        ]);
        expect(h.repo.maximumActive, 1);
        expect(
          result.results.cast<Map>().map((r) => r['outcome']),
          everyElement('succeeded'),
        );
        expect(h.activity?.kind, CommandLineActivityKind.replaceSource);
        expect(h.activity?.finished, true);
        expect(
          h.activity?.items.map((i) => i.status),
          everyElement(CommandLineItemStatus.succeeded),
        );
      });
    },
  );

  test('external commit requires re-review of only the remaining replacement items', () {
    scenario((h) {
      h.repo.candidates = [
        for (final s in h.repo.current.skills)
          WriteRepository.candidate(s.slotKey),
      ];
      h.repo.onReplacementCommit = () {
        h.repo.onReplacementCommit = null;
        // The receipt returned revision 8; somebody else commits revision 9
        // before the registry starts beta. A current-snapshot read would hide it.
        h.repo.publish();
      };
      final running = h.run('source replace');
      h.approve(7);
      expect(h.presenter.requests, hasLength(2));
      final stale = h.presenter.requests.last;
      expect(stale.staleReview, true);
      expect(stale.id, h.id);
      expect(stale.expiresAt, h.presenter.requests.first.expiresAt);
      expect(
        (stale.subject as CommandApprovalReplaceSource).items.map(
          (i) => i.skillId,
        ),
        ['beta', 'gamma'],
      );
      expect(h.repo.replaceSourceRequests.map((r) => r.expectedRevision), [
        7,
        8,
      ]);
      h.approve(9);
      final result = h.finish(running);
      expect(result.ok, true);
      expect(result.results.cast<Map>().map((r) => r['id']), [
        'alpha',
        'beta',
        'gamma',
      ]);
      expect(h.repo.replaceSourceRequests.map((r) => r.skillId.value), [
        'alpha',
        'beta',
        'beta',
        'gamma',
      ]);
      expect(h.repo.replaceSourceRequests.map((r) => r.expectedRevision), [
        7,
        8,
        9,
        10,
      ]);
    });
  });

  for (final keepGoing in [false, true]) {
    test(
      'replacement failure keeps commits and ${keepGoing ? 'continues' : 'skips'} later items',
      () {
        scenario((h) {
          h.repo.candidates = [
            for (final s in h.repo.current.skills)
              WriteRepository.candidate(s.slotKey),
          ];
          h.repo.failures[3] = WorkspaceErrorCode.ioFailure;
          final running = h.run('source replace', {'keepGoing': keepGoing});
          h.approve(7);
          final result = h.finish(running);
          expect(result.error?.code, 'partialBatch');
          expect(result.results.cast<Map>().map((r) => r['outcome']), [
            'succeeded',
            'failed',
            keepGoing ? 'succeeded' : 'skipped',
          ]);
          expect(
            h.repo.replaceSourceRequests.map((r) => r.expectedRevision),
            keepGoing ? [7, 8, 8] : [7, 8],
          );
          expect(jsonEncode(result.toJson()), isNot(contains('sensitive')));
        });
      },
    );
  }

  test('replacement committed pending advances to committedRevision', () {
    scenario((h) {
      h.repo.candidates = [
        for (final s in h.repo.current.skills)
          WriteRepository.candidate(s.slotKey),
      ];
      h.repo.pending.add(2);
      final running = h.run('source replace');
      h.approve(7);
      final result = h.finish(running);
      expect(result.ok, true);
      expect(
        (result.results.first as Map)['outcome'],
        'committedFinalizationPending',
      );
      expect((result.results.first as Map)['operationId'], 'pending-2');
      expect(h.repo.replaceSourceRequests.map((r) => r.expectedRevision), [
        7,
        8,
        9,
      ]);
    });
  });

  for (final failure in {
    WorkspaceErrorCode.agentRootOwnership: (
      'agentRootOwnershipRepairRequired',
      'settings',
    ),
    WorkspaceErrorCode.dirtyDraftResolutionRequired: (
      'actionRequired',
      'skillDetail',
    ),
    WorkspaceErrorCode.updateCandidateResolutionRequired: (
      'actionRequired',
      'updates',
    ),
  }.entries) {
    test('replacement maps ${failure.key.name} to App action', () {
      scenario((h) {
        h.repo.candidates = [
          for (final s in h.repo.current.skills)
            WriteRepository.candidate(s.slotKey),
        ];
        h.repo.failures[2] = failure.key;
        final running = h.run('source replace');
        h.approve(7);
        final result = h.finish(running);
        expect(result.error?.code, failure.value.$1);
        expect(result.error?.details['screen'], failure.value.$2);
        expect(result.results.cast<Map>().map((r) => r['outcome']), [
          'failed',
          'skipped',
          'skipped',
        ]);
      });
    });
  }

  for (final decision in ['deny', 'expire', 'cancel']) {
    test(
      'replacement $decision before approval makes no mutation or activity',
      () {
        scenario((h) {
          h.repo.candidates = [
            for (final s in h.repo.current.skills)
              WriteRepository.candidate(s.slotKey),
          ];
          final running = h.run('source replace', {'approvalTimeout': 600});
          if (decision == 'deny') {
            h.presenter.decide(const CommandApprovalDenied());
          } else if (decision == 'expire') {
            h.time.elapse(const Duration(minutes: 10));
          } else {
            h.finish(h.run('approvals cancel', {'id': h.id}));
          }
          final result = h.finish(running);
          expect(result.error?.code, switch (decision) {
            'deny' => 'approvalDenied',
            'expire' => 'approvalExpired',
            _ => 'approvalCancelled',
          });
          expect(h.repo.replaceSourceRequests, isEmpty);
          expect(h.activity, isNull);
        });
      },
    );
  }

  test('denying stale replacement review retains already committed rows', () {
    scenario((h) {
      h.repo.candidates = [
        for (final s in h.repo.current.skills)
          WriteRepository.candidate(s.slotKey),
      ];
      h.repo.onReplacementCommit = () {
        h.repo.onReplacementCommit = null;
        h.repo.publish();
      };
      final running = h.run('source replace');
      h.approve(7);
      h.presenter.decide(const CommandApprovalDenied());
      final result = h.finish(running);
      expect(result.error?.code, 'approvalDenied');
      expect(result.results.cast<Map>().map((r) => r['outcome']), [
        'succeeded',
        'skipped',
        'skipped',
      ]);
    });
  });

  test(
    'replacement timeout and connection cancellation preserve pending approval',
    () {
      scenario((h) {
        h.repo.candidates = [
          for (final s in h.repo.current.skills)
            WriteRepository.candidate(s.slotKey),
        ];
        final running = h.run('source replace', {'approvalTimeout': 0});
        expect(h.finish(running).error?.code, 'approvalPending');
        expect(h.presenter.withdrawn, isEmpty);
        h.approve(7);
        expect(h.status().ok, true);
        expect(h.repo.replaceSourceRequests, hasLength(3));
      });
    },
  );

  test(
    'replacement inspection retries web discovery as Git, preserving new ref',
    () {
      scenario((h) {
        h.repo.inspectionFailure = WorkspaceErrorCode.httpFailure;
        h.repo.inspectionFailureContext = {'reason': 'unexpectedStatus'};
        final running = h.run('source replace', {
          'selection': SkillSelection(refs: ['alpha']).toJson(),
          'to': 'https://example.test/catalog',
          'ref': 'new-ref',
          'dryRun': true,
        });
        final result = h.finish(running);
        expect(result.ok, true);
        expect(h.repo.inspectedSources.map((s) => s.kind), [
          WorkspaceSourceKind.wellKnown,
          WorkspaceSourceKind.git,
        ]);
        expect(
          h.repo.inspectedSources.map((s) => s.ref),
          everyElement('new-ref'),
        );
        expect(h.presenter.requests, isEmpty);
        expect(h.repo.replaceSourceRequests, isEmpty);
      });
    },
  );

  test('single pending admission, timeout, resume and terminal retention', () {
    scenario((h) {
      final first = h.run('remove');
      expect(h.presenter.requests, hasLength(1));
      final pending = h.finish(h.run('remove'));
      expect(pending.error?.code, 'approvalAlreadyPending');
      expect(pending.error?.details, {'id': h.id});
      h.time.elapse(const Duration(seconds: 90));
      expect(first().error?.code, 'approvalPending');
      expect(
        first().error?.details['expiresAt'],
        h.presenter.requests.single.expiresAt.toIso8601String(),
      );
      expect(h.presenter.withdrawn, isEmpty);
      final waiting = h.run('approvals wait', {'id': h.id});
      h.approve(42);
      final result = h.finish(waiting);
      expect(result.ok, true);
      expect(result.command, 'approvals wait');
      expect((result.data['result'] as Map)['command'], 'remove');
      expect(
        result.results.map((r) => (r as Map)['outcome']),
        everyElement('succeeded'),
      );
      expect(h.repo.calls, ['remove']);
      expect(h.repo.reviewedRevisions, [42]);
      expect(
        h.repo.skillSets.single,
        h.repo.current.skills.map((s) => s.id).toSet(),
      );
      expect(h.status().data['state'], 'terminal');
      expect(h.finish(h.run('approvals cancel', {'id': h.id})).ok, true);
      h.time.elapse(const Duration(minutes: 20));
      expect(h.status().ok, true);
      expect(h.presenter.withdrawn, isEmpty);
    });
  });

  test('denial is terminal and does not mutate or report activity', () {
    scenario((h) {
      final running = h.run('remove');
      h.presenter.decide(const CommandApprovalDenied());
      expect(h.finish(running).error?.code, 'approvalDenied');
      expect(h.repo.calls, isEmpty);
      expect(h.activity, isNull);
      expect(
        h.finish(h.run('approvals cancel', {'id': h.id})).error?.code,
        'approvalDenied',
      );
    });
  });

  for (final code in ['approvalExpired', 'approvalCancelled']) {
    test('$code withdraws once, and a late approval cannot execute', () {
      scenario((h) {
        final running = h.run('remove', {'approvalTimeout': 600});
        if (code == 'approvalExpired') {
          h.time.elapse(const Duration(minutes: 10));
        } else {
          expect(
            h.finish(h.run('approvals cancel', {'id': h.id})).error?.code,
            code,
          );
        }
        expect(h.finish(running).error?.code, code);
        expect(h.presenter.withdrawn, [h.id]);
        expect(h.repo.calls, isEmpty);
        expect(h.status().error?.code, code);
      });
    });
  }

  test(
    'connection cancellation and zero wait never withdraw or cancel execution',
    () {
      scenario((h) {
        final connection = CommandCancellation();
        CommandResult? result;
        unawaited(
          h.dispatcher
              .dispatch(
                CommandRequest(
                  command: 'remove',
                  arguments: {
                    'selection': SkillSelection(all: true).toJson(),
                    'approvalTimeout': 0,
                  },
                ),
                cancellation: connection,
              )
              .then((value) => result = value),
        );
        h.time.elapse(Duration.zero);
        unawaited(connection.cancel());
        h.time.elapse(Duration.zero);
        expect(result?.error?.code, 'approvalPending');
        expect(h.presenter.withdrawn, isEmpty);
        h.approve(7);
        expect(h.status().ok, true);
        expect(h.repo.calls, ['remove']);
        expect(h.repo.taskCancelled, false);
      });
    },
  );

  test('status exposes pending, executing, terminal and unknown ids', () {
    scenario((h) {
      h.repo.blockAt = 1;
      h.run('remove');
      expect(h.status().data['state'], 'pending');
      h.approve(7);
      expect(h.status().data['state'], 'executing');
      expect(h.activity?.finished, false);
      // App activity cancellation still cancels the independent task.
      h.container.read(commandLineActivityProvider.notifier).cancel();
      h.time.elapse(Duration.zero);
      expect(h.status().data['state'], 'terminal');
      expect(h.status().error?.code, 'operationCancelled');
      expect(h.repo.taskCancelled, true);
      for (final command in [
        'approvals wait',
        'approvals status',
        'approvals cancel',
      ]) {
        expect(
          h.finish(h.run(command, {'id': 'unknown'})).error?.code,
          'approvalNotFound',
        );
      }
    });
  });

  test(
    'stale snapshot re-presents same id, then approves a fresh revision',
    () {
      scenario((h) {
        h.repo.failures[1] = WorkspaceErrorCode.staleSnapshot;
        final running = h.run('remove');
        final expires = h.presenter.requests.single.expiresAt;
        h.approve(6);
        expect(h.presenter.requests, hasLength(2));
        expect(h.presenter.requests.last.staleReview, true);
        expect(h.presenter.requests.last.id, h.id);
        expect(h.presenter.requests.last.expiresAt, expires);
        expect(h.status().data['state'], 'pending');
        h.approve(8);
        expect(h.finish(running).ok, true);
        expect(h.repo.calls, ['remove', 'remove']);
        expect(h.repo.reviewedRevisions, [6, 8]);
      });
    },
  );

  test(
    'committed pending maps every item and activity to committed outcome',
    () {
      scenario((h) {
        h.repo.pending.add(1);
        final running = h.run('remove');
        expect(h.activity, isNull);
        h.approve(7);
        final result = h.finish(running);
        expect(result.ok, true);
        for (final item in result.results.cast<Map>()) {
          expect(item['outcome'], 'committedFinalizationPending');
          expect(item['operationId'], 'pending-1');
        }
        expect(h.activity?.kind, CommandLineActivityKind.remove);
        expect(
          h.activity?.items.map((i) => i.status),
          everyElement(CommandLineItemStatus.committedFinalizationPending),
        );
        expect(h.activity?.finished, true);
      });
    },
  );

  test(
    'operation failure fails all items with stable code, no diagnostics',
    () {
      scenario((h) {
        h.repo.failures[1] = WorkspaceErrorCode.ioFailure;
        final running = h.run('remove');
        h.approve(7);
        final result = h.finish(running);
        expect(result.error?.code, 'ioFailure');
        expect(
          result.results.cast<Map>().map((r) => r['outcome']),
          everyElement('failed'),
        );
        expect(jsonEncode(result.toJson()), isNot(contains('sensitive')));
        expect(jsonEncode(result.toJson()), isNot(contains('/private')));
      });
    },
  );

  test('dry runs disclose removal and tag facts with zero mutations', () {
    scenario((h) {
      h.repo.current = testSnapshot();
      final removal = h.finish(h.run('remove', {'dryRun': true}));
      expect(removal.results.first, {
        'id': 'skill-1',
        'slotKey': 'alpha',
        'outcome': 'wouldSucceed',
        'activatedAgents': ['Codex', 'Claude Code'],
        'unpublishedDraft': true,
      });
      expect((removal.results.last as Map)['unpublishedDraft'], false);
      final tag = h.finish(
        h.run('tag delete', {'tag': 'tEsTiNg', 'dryRun': true}),
      );
      expect(tag.data, {
        'dryRun': true,
        'tag': 'Testing',
        'assignedSkillCount': 1,
      });
      expect(h.presenter.requests, isEmpty);
      expect(h.repo.calls, isEmpty);
      expect(h.activity, isNull);
      expect(jsonEncode(removal.toJson()), isNot(contains('/private')));
    });
  });

  test(
    'empty filter creates no approval and missing tag fails even on dry run',
    () {
      scenario((h) {
        expect(
          h
              .finish(
                h.run('remove', {
                  'selection': SkillSelection(tags: ['missing']).toJson(),
                }),
              )
              .results,
          isEmpty,
        );
        for (final dry in [true, false]) {
          expect(
            h
                .finish(h.run('tag delete', {'tag': 'missing', 'dryRun': dry}))
                .error
                ?.code,
            'tagNotFound',
          );
        }
        expect(h.presenter.requests, isEmpty);
        expect(h.repo.calls, isEmpty);
      });
    },
  );

  for (final approve in [true, false]) {
    test(
      'tag delete ${approve ? 'approved' : 'denied'} never reports Skill activity',
      () {
        scenario((h) {
          final running = h.run('tag delete', {'tag': 'Testing'});
          expect(
            (h.presenter.requests.single.subject as CommandApprovalDeleteTag)
                .tagId,
            'tag-1',
          );
          expect(h.repo.calls, isEmpty);
          h.presenter.decide(
            approve
                ? const CommandApprovalApproved(reviewedRevision: 7)
                : const CommandApprovalDenied(),
          );
          final result = h.finish(running);
          expect(result.ok, approve);
          expect(result.error?.code, approve ? null : 'approvalDenied');
          expect(h.repo.calls, approve ? ['tag delete tag-1'] : isEmpty);
          expect(h.activity, isNull);
        });
      },
    );
  }

  test('wire arguments reject bypasses and invalid approval timeouts', () {
    scenario((h) {
      for (final args in [
        {'approvalTimeout': -1},
        {'approvalTimeout': 601},
        {'approvalTimeout': '90'},
        {'yes': true},
        {'skipApproval': true},
      ]) {
        expect(h.finish(h.run('remove', args)).error?.code, 'usage');
      }
      expect(h.presenter.requests, isEmpty);
      expect(h.repo.calls, isEmpty);
    });
  });
}

final class _Harness {
  _Harness(this.time) {
    var next = 0;
    registry = CommandApprovalRegistry(
      presenter: presenter,
      repository: () => repo,
      clock: () => time.getClock(DateTime.utc(2026, 10, 20)).now(),
      timer: Timer.new,
      nextId: () => 'ap_test${next++}',
      activity: CommandLineActivityReporter(
        controller: () => container.read(commandLineActivityProvider.notifier),
        agentName: (id) => id,
      ),
    );
    dispatcher = CommandHostDispatcher(
      approvalCommandHandlers(
        skillsLock: () => null,
        registry: registry,
        repository: () => repo,
        snapshot: () => repo.current,
        updates: testUpdates,
        agents: () async => [
          testAgent(),
          testAgent(id: 'claude', name: 'Claude Code'),
        ],
      ),
    );
  }
  final FakeAsync time;
  final repo = WriteRepository();
  final presenter = ApprovalPresenter();
  final container = ProviderContainer();
  late final CommandApprovalRegistry registry;
  late final CommandHostDispatcher dispatcher;
  String get id => presenter.requests.first.id;
  CommandLineActivity? get activity =>
      container.read(commandLineActivityProvider);
  CommandResult status() => registry.status(id);
  void approve(int revision) {
    presenter.decide(CommandApprovalApproved(reviewedRevision: revision));
    time.elapse(Duration.zero);
  }

  CommandResult Function() run(
    String command, [
    Map<String, Object?> args = const {},
  ]) {
    CommandResult? result;
    unawaited(
      dispatcher
          .dispatch(
            CommandRequest(
              command: command,
              arguments: {
                if (command == 'source replace') 'to': 'new/repo',
                if (command == 'remove' || command == 'source replace')
                  'selection': SkillSelection(all: true).toJson(),
                ...args,
              },
            ),
          )
          .then((value) => result = value),
    );
    time.flushMicrotasks();
    return () => result!;
  }

  CommandResult finish(CommandResult Function() result) {
    time.elapse(Duration.zero);
    return result();
  }
}
