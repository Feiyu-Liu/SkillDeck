import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_manager/features/translation/presentation/view_models/skill_translation_view_model.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_translation/skills_translation.dart';

import '../../../../support/fake_app_translation_repository.dart';
import '../../../../support/fake_skill_browser_repository.dart';

void main() {
  test(
    'restores full cache first and can show description cache offline',
    () async {
      const source = '---\ndescription: Purpose.\n---\n# Private body';
      final provider = _ControlledProvider();
      final setup = _setup(source: source, provider: provider);
      addTearDown(setup.container.dispose);
      for (final (scope, content) in [
        (TranslationScope.fullDocument, '---\ndescription: 全文说明\n---\n# 全文'),
        (TranslationScope.descriptionOnly, '简短说明'),
      ]) {
        setup.cache.values[TranslationCacheKey(
          slotKey: setup.skill.slotKey,
          contentHash: setup.skill.contentHash,
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
          scope: scope,
        )] = CompletedTranslation(
          slotKey: setup.skill.slotKey,
          contentHash: setup.skill.contentHash,
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
          translatedContent: content,
          scope: scope,
          provenance: TranslationProvenance(providerIdentifier: 'cached'),
        );
      }
      await setup.open();
      final viewModel = setup.container.read(
        skillTranslationViewModelProvider.notifier,
      );
      expect(
        setup.container.read(skillTranslationViewModelProvider).activeScope,
        TranslationScope.fullDocument,
      );

      viewModel.showOriginalContent();
      viewModel.showCachedTranslation(TranslationScope.descriptionOnly);
      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.activeScope, TranslationScope.descriptionOnly);
      expect(state.translatedDescription, '简短说明');
      expect(state.cachedTranslations, hasLength(2));
      expect(state.showOriginal, isFalse);
      expect(provider.job, isNull);
    },
  );

  test(
    'description-only result is scoped and leaves body cache independent',
    () async {
      final provider = _ControlledProvider();
      final setup = _setup(
        source: '---\ndescription: Purpose.\n---\n# Private body',
        provider: provider,
      );
      addTearDown(setup.container.dispose);
      setup.cache.values[TranslationCacheKey(
        slotKey: setup.skill.slotKey,
        contentHash: setup.skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
      )] = CompletedTranslation(
        slotKey: setup.skill.slotKey,
        contentHash: setup.skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '---\ndescription: 全文说明\n---\n# 全文',
        provenance: TranslationProvenance(providerIdentifier: 'cached'),
      );
      await setup.open();
      final pending = setup.container
          .read(skillTranslationViewModelProvider.notifier)
          .translate(TranslationScope.descriptionOnly);
      await _eventually(() => provider.job != null);
      expect(provider.lastScope, TranslationScope.descriptionOnly);
      provider.job!.complete(
        CompletedTranslation(
          slotKey: setup.skill.slotKey,
          contentHash: setup.skill.contentHash,
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
          scope: TranslationScope.descriptionOnly,
          translatedContent: '简短说明',
          provenance: TranslationProvenance(providerIdentifier: 'controlled'),
        ),
      );
      await pending;
      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.activeScope, TranslationScope.descriptionOnly);
      expect(state.translatedContent, '简短说明');
      expect(
        state.cachedTranslations.keys,
        containsAll(TranslationScope.values),
      );
      expect(
        state
            .cachedTranslations[TranslationScope.fullDocument]!
            .translatedContent,
        contains('# 全文'),
      );
    },
  );

  test(
    'unconfigured translation warns without starting and unlocks after save',
    () async {
      final provider = _ControlledProvider();
      final setup = _setup(
        source: '# Alpha',
        provider: provider,
        settingsStore: MemoryTranslationSettingsStore(),
        translationCache: _cacheSeededWith('# Cached'),
      );
      addTearDown(setup.container.dispose);
      await setup.open();
      final events = _recordNotificationEvents(setup.container);
      final viewModel = setup.container.read(
        skillTranslationViewModelProvider.notifier,
      );
      viewModel.showOriginalContent();
      final before = setup.container.read(skillTranslationViewModelProvider);
      await viewModel.translate();
      expect(provider.job, isNull);
      expect(
        setup.container.read(skillTranslationViewModelProvider),
        same(before),
      );
      expect(events, hasLength(1));
      expect(
        events.single.notification.message,
        AppNotificationMessage.translationConfigureFirst,
      );
      expect(
        events.single.notification.severity,
        AppNotificationSeverity.warning,
      );
      expect(before.translatedContent, '# Cached');

      expect(
        await viewModel.saveProfile(TranslationProviderProfile.defaults()),
        isTrue,
      );
      final translating = viewModel.translate();
      await _eventually(() => provider.job != null);
      await viewModel.cancel();
      await translating;
    },
  );

  test('refreshes the cached list description after translation', () async {
    final provider = _ControlledProvider();
    final setup = _setup(
      source: '''---
description: Original description
---
# Alpha''',
      provider: provider,
    );
    addTearDown(setup.container.dispose);
    await setup.open();
    final listKey = (
      slotKey: setup.skill.slotKey,
      contentHash: setup.skill.contentHash,
    );
    final subscription = setup.container.listen(
      cachedSkillDescriptionProvider(listKey),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    expect(
      await setup.container.read(
        cachedSkillDescriptionProvider(listKey).future,
      ),
      isNull,
    );

    final translating = setup.container
        .read(skillTranslationViewModelProvider.notifier)
        .translate();
    await _eventually(() => provider.job != null);
    provider.job!.complete(
      CompletedTranslation(
        slotKey: setup.skill.slotKey,
        contentHash: setup.skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '''---
description: 已翻译描述
---
# Alpha''',
        provenance: TranslationProvenance(providerIdentifier: 'controlled'),
      ),
    );
    await translating;

    await _eventually(
      () => switch (setup.container.read(
        cachedSkillDescriptionProvider(listKey),
      )) {
        AsyncData(value: '已翻译描述') => true,
        _ => false,
      },
    );
  });

  test(
    'reuses a resolved list description after its listener leaves',
    () async {
      final setup = _setup(source: '# Alpha', provider: _ControlledProvider());
      addTearDown(setup.container.dispose);
      final key = (
        slotKey: setup.skill.slotKey,
        contentHash: setup.skill.contentHash,
      );
      final first = setup.container.listen(
        cachedSkillDescriptionProvider(key),
        (_, _) {},
      );
      expect(
        await setup.container.read(cachedSkillDescriptionProvider(key).future),
        isNull,
      );
      expect(setup.cache.readKeys, hasLength(2));
      first.close();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final second = setup.container.listen(
        cachedSkillDescriptionProvider(key),
        (_, _) {},
      );
      addTearDown(second.close);
      expect(
        await setup.container.read(cachedSkillDescriptionProvider(key).future),
        isNull,
      );
      expect(setup.cache.readKeys, hasLength(2));
    },
  );

  testWidgets('releases the list description after five minutes', (
    tester,
  ) async {
    final cache = MemoryTranslationCache();
    final repository = fakeAppTranslationRepository(cache: cache);
    const key = (slotKey: 'alpha', contentHash: 'hash');

    Widget page(bool visible) => ProviderScope(
      overrides: [
        appTranslationRepositoryProvider.overrideWithValue(repository),
      ],
      child: visible
          ? Consumer(
              builder: (context, ref, _) {
                ref.watch(cachedSkillDescriptionProvider(key));
                return const SizedBox.shrink();
              },
            )
          : const SizedBox.shrink(),
    );

    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    expect(cache.readKeys, hasLength(2));
    await tester.pumpWidget(page(false));
    await tester.pump(const Duration(minutes: 5, seconds: 1));
    await tester.pumpWidget(page(true));
    await tester.pumpAndSettle();
    expect(cache.readKeys, hasLength(4));
  });

  test(
    'publishes cumulative block replacements as each Draft arrives',
    () async {
      final source = '# Alpha\n\nOriginal';
      final provider = _ControlledProvider();
      final setup = _setup(source: source, provider: provider);
      addTearDown(setup.container.dispose);
      await setup.open();
      final notifications = _recordNotifications(setup.container);

      final translation = setup.container.read(
        skillTranslationViewModelProvider.notifier,
      );
      final translating = translation.translate();
      await _eventually(() => provider.job != null);
      provider.job!.emitDraft(
        TranslationDraft(
          translatedBlocks: {const MarkdownBlockId(0, 7): '# 阿尔法'},
          translatedDescription: null,
          completedBlockCount: 1,
          totalBlockCount: 2,
        ),
      );
      await _eventually(
        () => setup.container
            .read(skillTranslationViewModelProvider)
            .translatedBlocks
            .isNotEmpty,
      );

      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.phase, SkillTranslationPhase.translating);
      expect(state.translatedBlocks, {const MarkdownBlockId(0, 7): '# 阿尔法'});
      expect(state.translatedContent, isNull);
      expect(state.completedBlockCount, 1);
      expect(state.totalBlockCount, 2);

      provider.job!.complete(
        CompletedTranslation(
          slotKey: 'alpha',
          contentHash: setup.skill.contentHash,
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
          translatedContent: '# 阿尔法\n\n原文',
          provenance: TranslationProvenance(providerIdentifier: 'controlled'),
        ),
      );
      await translating;
      expect(
        setup.container
            .read(skillTranslationViewModelProvider)
            .translatedBlocks,
        {const MarkdownBlockId(0, 7): '# 阿尔法'},
      );
      expect(notifications, [
        AppNotificationMessage.translationStarted,
        AppNotificationMessage.translationProgress,
        AppNotificationMessage.translationCompleted,
      ]);
    },
  );

  test(
    'failure discards every partial replacement and restores cache',
    () async {
      final source = '# Alpha\n\nOriginal';
      final provider = _ControlledProvider();
      final setup = _setup(source: source, provider: provider);
      setup.cache.values[TranslationCacheKey(
        slotKey: 'alpha',
        contentHash: setup.skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
      )] = CompletedTranslation(
        slotKey: 'alpha',
        contentHash: setup.skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: '# Cached',
        provenance: TranslationProvenance(providerIdentifier: 'cached'),
      );
      addTearDown(setup.container.dispose);
      await setup.open();
      final notifications = _recordNotifications(setup.container);
      final events = _recordNotificationEvents(setup.container);
      await _eventually(
        () =>
            setup.container
                .read(skillTranslationViewModelProvider)
                .translatedContent ==
            '# Cached',
      );

      final translating = setup.container
          .read(skillTranslationViewModelProvider.notifier)
          .translate();
      await _eventually(() => provider.job != null);
      provider.job!.emitDraft(
        TranslationDraft(
          translatedBlocks: {const MarkdownBlockId(0, 7): '# Partial'},
          translatedDescription: null,
          completedBlockCount: 1,
          totalBlockCount: 2,
        ),
      );
      provider.job!.complete(
        TranslationFailure(
          code: TranslationFailureCode.providerUnavailable,
          reason: 'Provider unavailable.',
          providerErrorCode: 'gateway_error',
          providerErrorMessage: 'Provider echoed private-source',
        ),
      );
      await translating;

      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.phase, SkillTranslationPhase.failed);
      expect(state.translatedBlocks, isEmpty);
      expect(state.translatedContent, '# Cached');
      expect(
        state.failureCode,
        'translation_${TranslationFailureCode.providerUnavailable.name}',
      );
      expect(notifications, [
        AppNotificationMessage.translationStarted,
        AppNotificationMessage.translationProgress,
        AppNotificationMessage.translationFailed,
      ]);
      expect(
        events.last.notification.providerError,
        'gateway_error: Provider echoed private-source',
      );
    },
  );

  test(
    'cache publication failure discards partials and preserves old cache',
    () async {
      const source = '''---
description: Original description
---
# Alpha

Original''';
      const cachedContent = '''---
description: Cached description
---
# Cached''';
      final provider = _ControlledProvider();
      final setup = _setup(source: source, provider: provider);
      final cacheKey = TranslationCacheKey(
        slotKey: 'alpha',
        contentHash: setup.skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
      );
      final cached = CompletedTranslation(
        slotKey: 'alpha',
        contentHash: setup.skill.contentHash,
        documentIdentifier: 'SKILL.md',
        targetLanguage: TargetLanguage('zh-Hans'),
        translatedContent: cachedContent,
        provenance: TranslationProvenance(providerIdentifier: 'cached'),
      );
      setup.cache.values[cacheKey] = cached;
      addTearDown(setup.container.dispose);
      await setup.open();
      final notifications = _recordNotifications(setup.container);
      await _eventually(
        () =>
            setup.container
                .read(skillTranslationViewModelProvider)
                .translatedContent ==
            cachedContent,
      );

      final translating = setup.container
          .read(skillTranslationViewModelProvider.notifier)
          .translate();
      await _eventually(() => provider.job != null);
      provider.job!.emitDraft(
        TranslationDraft(
          translatedBlocks: {const MarkdownBlockId(0, 7): '# Partial'},
          translatedDescription: 'Partial description',
          completedBlockCount: 2,
          totalBlockCount: 2,
        ),
      );
      await _eventually(
        () => setup.container
            .read(skillTranslationViewModelProvider)
            .translatedBlocks
            .isNotEmpty,
      );
      setup.cache.saveError = StateError('sensitive cache failure');
      provider.job!.complete(
        CompletedTranslation(
          slotKey: 'alpha',
          contentHash: setup.skill.contentHash,
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
          translatedContent: '# New translation',
          provenance: TranslationProvenance(providerIdentifier: 'controlled'),
        ),
      );

      await expectLater(translating, completes);

      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.phase, SkillTranslationPhase.failed);
      expect(state.failureCode, 'translation_cache_write_failed');
      expect(state.translatedBlocks, isEmpty);
      expect(state.completedBlockCount, 0);
      expect(state.totalBlockCount, 0);
      expect(state.translatedContent, cachedContent);
      expect(state.translatedDescription, 'Cached description');
      expect(setup.cache.values[cacheKey], same(cached));
      expect(notifications, [
        AppNotificationMessage.translationStarted,
        AppNotificationMessage.translationProgress,
        AppNotificationMessage.translationFailed,
      ]);
    },
  );

  test(
    'cancellation discards Draft replacements and restores original',
    () async {
      final provider = _ControlledProvider();
      final setup = _setup(source: '# Alpha\n\nOriginal', provider: provider);
      addTearDown(setup.container.dispose);
      await setup.open();
      final notifications = _recordNotifications(setup.container);
      final viewModel = setup.container.read(
        skillTranslationViewModelProvider.notifier,
      );
      final translating = viewModel.translate();
      await _eventually(() => provider.job != null);
      provider.job!.emitDraft(
        TranslationDraft(
          translatedBlocks: {const MarkdownBlockId(0, 7): '# Partial'},
          translatedDescription: null,
          completedBlockCount: 1,
          totalBlockCount: 2,
        ),
      );

      await viewModel.cancel();
      await translating;

      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.phase, SkillTranslationPhase.cancelled);
      expect(state.translatedBlocks, isEmpty);
      expect(state.translatedContent, isNull);
      expect(state.translatedDescription, isNull);
      expect(notifications, [
        AppNotificationMessage.translationStarted,
        AppNotificationMessage.translationProgress,
        AppNotificationMessage.translationCancelling,
        AppNotificationMessage.translationCancelled,
      ]);
    },
  );

  test(
    'publishes content readiness only after the cache lookup resolves',
    () async {
      final cacheResult = Completer<CompletedTranslation?>();
      final cache = MemoryTranslationCache()
        ..readHandler = (_) => cacheResult.future;
      final setup = _setup(
        source: '# Alpha',
        provider: _ControlledProvider(),
        translationCache: cache,
      );
      addTearDown(setup.container.dispose);

      setup.container.read(skillTranslationViewModelProvider);
      await setup.container.read(skillBrowserViewModelProvider.notifier).load();
      await _eventually(
        () =>
            setup.container.read(skillTranslationViewModelProvider).request !=
            null,
      );

      var state = setup.container.read(skillTranslationViewModelProvider);
      final sourceDocument = state.request!;
      expect(state.phase, SkillTranslationPhase.loadingCache);
      expect(state.isCacheResolvedFor(sourceDocument), isFalse);
      expect(state.canTranslate, isFalse);

      cacheResult.complete(null);
      await _eventually(
        () =>
            setup.container.read(skillTranslationViewModelProvider).phase ==
            SkillTranslationPhase.ready,
      );

      state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.isCacheResolvedFor(sourceDocument), isTrue);
      expect(state.canTranslate, isTrue);
    },
  );

  test(
    'settings failure releases a waiting document to use its source',
    () async {
      final settingsStore = MemoryTranslationSettingsStore()
        ..readError = StateError('unavailable');
      final setup = _setup(
        source: '# Alpha',
        provider: _ControlledProvider(),
        settingsStore: settingsStore,
      );
      addTearDown(setup.container.dispose);

      setup.container.read(skillTranslationViewModelProvider);
      await setup.container.read(skillBrowserViewModelProvider.notifier).load();
      await _eventually(() {
        final state = setup.container.read(skillTranslationViewModelProvider);
        return state.settingsStatus == TranslationSettingsStatus.failure &&
            state.request != null &&
            state.phase == SkillTranslationPhase.ready;
      });

      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.isCacheResolvedFor(state.request!), isTrue);
      expect(state.translatedContent, isNull);
      expect(state.failureCode, 'settings_load_failed');
      expect(state.canTranslate, isFalse);
    },
  );

  test('cache failure resolves the document with source fallback', () async {
    final cache = MemoryTranslationCache()
      ..readError = StateError('unavailable');
    final setup = _setup(
      source: '# Alpha',
      provider: _ControlledProvider(),
      translationCache: cache,
    );
    addTearDown(setup.container.dispose);

    await setup.open();

    final state = setup.container.read(skillTranslationViewModelProvider);
    expect(state.phase, SkillTranslationPhase.ready);
    expect(state.isCacheResolvedFor(state.request!), isTrue);
    expect(state.translatedContent, isNull);
    expect(state.failureCode, 'cache_unavailable');
    expect(state.canTranslate, isTrue);
  });

  test('selection seam cancels the active Job and clears its Draft', () async {
    final provider = _ControlledProvider();
    final setup = _setup(
      source: '# Alpha',
      provider: provider,
      additionalDocuments: const {'guide.md': '# Guide'},
    );
    addTearDown(setup.container.dispose);
    await setup.open();
    final events = _recordNotificationEvents(setup.container);
    unawaited(
      setup.container
          .read(skillTranslationViewModelProvider.notifier)
          .translate(),
    );
    await _eventually(() => provider.job != null);
    final activeJob = provider.job!;
    activeJob.emitDraft(
      TranslationDraft(
        translatedBlocks: {const MarkdownBlockId(0, 7): '# Partial'},
        translatedDescription: null,
        completedBlockCount: 1,
        totalBlockCount: 1,
      ),
    );

    await setup.container
        .read(skillBrowserViewModelProvider.notifier)
        .selectDocument('guide.md');
    await _eventually(() {
      final state = setup.container.read(skillTranslationViewModelProvider);
      return state.request?.documentIdentifier == 'guide.md' &&
          state.phase == SkillTranslationPhase.ready;
    });

    final state = setup.container.read(skillTranslationViewModelProvider);
    expect(activeJob.cancelled, isTrue);
    expect(state.translatedBlocks, isEmpty);
    expect(state.translatedContent, isNull);
    expect(events.last.kind, AppNotificationEventKind.taskDismissed);
  });

  test(
    'a cached translation renders until the reader asks for the original',
    () async {
      final setup = _setup(
        source: '# Alpha',
        provider: _ControlledProvider(),
        translationCache: _cacheSeededWith('# 阿尔法'),
      );
      addTearDown(setup.container.dispose);
      await setup.open();
      final viewModel = setup.container.read(
        skillTranslationViewModelProvider.notifier,
      );

      expect(
        setup.container
            .read(skillTranslationViewModelProvider)
            .showsTranslation,
        isTrue,
      );

      viewModel.showOriginalContent();

      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(state.showOriginal, isTrue);
      expect(state.showsTranslation, isFalse);
      expect(
        state.translatedContent,
        '# 阿尔法',
        reason: 'showing the original must not discard the cached translation',
      );
    },
  );

  test('selecting another document restores the translation view', () async {
    final setup = _setup(
      source: '# Alpha',
      provider: _ControlledProvider(),
      additionalDocuments: const {'guide.md': '# Guide'},
      translationCache: _cacheSeededWith('# 阿尔法'),
    );
    addTearDown(setup.container.dispose);
    await setup.open();
    setup.container
        .read(skillTranslationViewModelProvider.notifier)
        .showOriginalContent();

    await setup.container
        .read(skillBrowserViewModelProvider.notifier)
        .selectDocument('guide.md');
    await _eventually(() {
      final state = setup.container.read(skillTranslationViewModelProvider);
      return state.request?.documentIdentifier == 'guide.md' &&
          state.phase == SkillTranslationPhase.ready;
    });

    expect(
      setup.container.read(skillTranslationViewModelProvider).showOriginal,
      isFalse,
    );
  });

  test('starting a translation leaves show-original mode', () async {
    final provider = _ControlledProvider();
    final setup = _setup(
      source: '# Alpha',
      provider: provider,
      translationCache: _cacheSeededWith('# 阿尔法'),
    );
    addTearDown(setup.container.dispose);
    await setup.open();
    final viewModel = setup.container.read(
      skillTranslationViewModelProvider.notifier,
    );
    viewModel.showOriginalContent();

    final translating = viewModel.translate();
    await _eventually(() => provider.job != null);

    expect(
      setup.container.read(skillTranslationViewModelProvider).showOriginal,
      isFalse,
    );
    provider.job!.cancel();
    await translating;
  });

  test(
    'deleting the cache drops the translation and reports the Slot',
    () async {
      final setup = _setup(
        source: '# Alpha',
        provider: _ControlledProvider(),
        translationCache: _cacheSeededWith('# 阿尔法'),
      );
      addTearDown(setup.container.dispose);
      await setup.open();
      final messages = _recordNotifications(setup.container);

      final deleted = await setup.container
          .read(skillTranslationViewModelProvider.notifier)
          .deleteCachedTranslation();

      final state = setup.container.read(skillTranslationViewModelProvider);
      expect(deleted, isTrue);
      expect(setup.cache.deletedSlotKeys, ['alpha']);
      expect(state.translatedContent, isNull);
      expect(state.translatedBlocks, isEmpty);
      expect(state.hasTranslation, isFalse);
      expect(state.showOriginal, isFalse);
      expect(
        messages,
        contains(AppNotificationMessage.translationCacheDeleted),
      );
    },
  );

  test('a failed cache deletion keeps the translation on screen', () async {
    final cache = _cacheSeededWith('# 阿尔法')
      ..deleteSlotError = StateError('locked');
    final setup = _setup(
      source: '# Alpha',
      provider: _ControlledProvider(),
      translationCache: cache,
    );
    addTearDown(setup.container.dispose);
    await setup.open();

    final deleted = await setup.container
        .read(skillTranslationViewModelProvider.notifier)
        .deleteCachedTranslation();

    final state = setup.container.read(skillTranslationViewModelProvider);
    expect(deleted, isFalse);
    expect(state.translatedContent, '# 阿尔法');
    expect(state.showsTranslation, isTrue);
  });
}

/// A cache that answers every lookup with [translatedContent], standing in for
/// a Skill whose documents were translated in an earlier session.
MemoryTranslationCache _cacheSeededWith(String translatedContent) =>
    MemoryTranslationCache()
      ..readHandler = (key) async => CompletedTranslation(
        slotKey: key.slotKey,
        contentHash: key.contentHash,
        documentIdentifier: key.documentIdentifier,
        targetLanguage: key.targetLanguage,
        translatedContent: translatedContent,
        provenance: TranslationProvenance(providerIdentifier: 'cached'),
      );

List<AppNotificationMessage?> _recordNotifications(
  ProviderContainer container,
) {
  final messages = <AppNotificationMessage?>[];
  final subscription = container.listen(appNotificationControllerProvider, (
    _,
    next,
  ) {
    if (next != null) messages.add(next.notification.message);
  });
  addTearDown(subscription.close);
  return messages;
}

List<AppNotificationEvent> _recordNotificationEvents(
  ProviderContainer container,
) {
  final events = <AppNotificationEvent>[];
  final subscription = container.listen(appNotificationControllerProvider, (
    _,
    next,
  ) {
    if (next != null) events.add(next);
  });
  addTearDown(subscription.close);
  return events;
}

({
  ProviderContainer container,
  InstalledSkill skill,
  MemoryTranslationCache cache,
  FakeSkillBrowserRepository browserRepository,
  Future<void> Function() open,
})
_setup({
  required String source,
  required _ControlledProvider provider,
  Map<String, String> additionalDocuments = const {},
  MemoryTranslationCache? translationCache,
  MemoryTranslationSettingsStore? settingsStore,
}) {
  final skill = testSkill(slotKey: 'alpha', displayName: 'Alpha');
  final browserRepository = FakeSkillBrowserRepository(
    catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
    documents: {'alpha': source},
    additionalDocuments: {'alpha': additionalDocuments},
  );
  final cache = translationCache ?? MemoryTranslationCache();
  final translationRepository = fakeAppTranslationRepository(
    settingsStore: settingsStore,
    cache: cache,
    providerFactory: _ControlledFactory(provider),
  );
  final container = ProviderContainer(
    overrides: [
      skillBrowserRepositoryProvider.overrideWithValue(browserRepository),
      skillBrowserCatalogAuthorityProvider.overrideWithValue(
        SkillBrowserCatalogAuthority.repository,
      ),
      appTranslationRepositoryProvider.overrideWithValue(translationRepository),
      activeTranslationRequestProvider.overrideWith((ref) {
        final browser = ref.watch(skillBrowserViewModelProvider);
        final selected = browser.selectedSkill;
        final document = browser.document;
        final path = browser.selectedDocumentPath;
        final contentHash = browser.documentContentHash;
        if (selected == null ||
            document == null ||
            path == null ||
            contentHash == null) {
          return null;
        }
        return SourceDocument(
          slotKey: selected.slotKey,
          contentHash: contentHash,
          documentIdentifier: path,
          content: document,
        );
      }),
    ],
  );
  return (
    container: container,
    skill: skill,
    cache: cache,
    browserRepository: browserRepository,
    open: () async {
      container.read(skillTranslationViewModelProvider);
      await container
          .read(skillTranslationViewModelProvider.notifier)
          .reloadSettings();
      await container.read(skillBrowserViewModelProvider.notifier).load();
      await _eventually(
        () =>
            container.read(skillTranslationViewModelProvider).phase ==
            SkillTranslationPhase.ready,
      );
    },
  );
}

final class _ControlledFactory implements AppTranslationProviderFactory {
  const _ControlledFactory(this.provider);

  final _ControlledProvider provider;

  @override
  TranslationProvider create({
    required TranslationProviderProfile profile,
    required String? apiKey,
  }) => provider;
}

final class _ControlledProvider implements TranslationProvider {
  _ControlledJob? job;
  TranslationScope? lastScope;

  @override
  TranslationJob start({
    required SourceDocument sourceDocument,
    required TargetLanguage targetLanguage,
    TranslationScope scope = TranslationScope.fullDocument,
  }) {
    lastScope = scope;
    return job = _ControlledJob();
  }
}

final class _ControlledJob implements TranslationJob {
  final _drafts = StreamController<TranslationDraft>.broadcast(sync: true);
  final _result = Completer<TranslationJobOutcome>();
  bool cancelled = false;

  @override
  Stream<TranslationDraft> get drafts => _drafts.stream;

  @override
  Future<TranslationJobOutcome> get result => _result.future;

  void emitDraft(TranslationDraft draft) => _drafts.add(draft);

  void complete(TranslationJobOutcome outcome) {
    _drafts.close();
    _result.complete(outcome);
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!_drafts.isClosed) await _drafts.close();
    if (!_result.isCompleted) {
      _result.complete(const TranslationJobCancellation());
    }
  }
}

Future<void> _eventually(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) return;
    await Future<void>.value();
  }
  fail('Condition did not become true.');
}
