import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_manager/features/translation/translation_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_translation/skills_translation.dart';

enum TranslationSettingsStatus { loading, ready, failure }

enum SkillTranslationPhase {
  idle,
  loadingCache,
  ready,
  translating,
  cancelling,
  failed,
  cancelled,
}

final class SkillTranslationState {
  const SkillTranslationState({
    this.settingsStatus = TranslationSettingsStatus.loading,
    this.phase = SkillTranslationPhase.idle,
    this.settings,
    this.request,
    this.translatedContent,
    this.translatedDescription,
    this.failureCode,
    this.completedBlockCount = 0,
    this.totalBlockCount = 0,
    this.translatedBlocks = const {},
    this.showOriginal = false,
    this.activeScope = TranslationScope.fullDocument,
    this.cachedTranslations = const {},
  });

  final TranslationSettingsStatus settingsStatus;
  final SkillTranslationPhase phase;
  final AppTranslationSettings? settings;
  final SourceDocument? request;
  final String? translatedContent;
  final String? translatedDescription;
  final String? failureCode;
  final int completedBlockCount;
  final int totalBlockCount;
  final Map<MarkdownBlockId, String> translatedBlocks;

  /// Whether the reader asked to see the original document even though a
  /// translation is available. Toggling this never discards the translation.
  final bool showOriginal;
  final TranslationScope activeScope;
  final Map<TranslationScope, CompletedTranslation> cachedTranslations;

  bool get canTranslateDescription =>
      request?.documentIdentifier == 'SKILL.md' &&
      readTranslatableSkillDescription(request!.content) != null;

  bool hasCached(TranslationScope scope) =>
      cachedTranslations.containsKey(scope);

  /// Whether a cached or freshly produced translation exists for [request].
  bool get hasTranslation =>
      translatedContent != null || translatedBlocks.isNotEmpty;

  /// Whether the detail page is currently rendering that translation.
  bool get showsTranslation => hasTranslation && !showOriginal;

  bool get canTranslate =>
      settingsStatus == TranslationSettingsStatus.ready &&
      request != null &&
      switch (phase) {
        SkillTranslationPhase.ready ||
        SkillTranslationPhase.failed ||
        SkillTranslationPhase.cancelled => true,
        _ => false,
      };

  bool get isBusy =>
      phase == SkillTranslationPhase.translating ||
      phase == SkillTranslationPhase.cancelling;

  bool isCacheResolvedFor(SourceDocument sourceDocument) =>
      request == sourceDocument &&
      switch (phase) {
        SkillTranslationPhase.idle ||
        SkillTranslationPhase.loadingCache => false,
        _ => true,
      };

  TranslationProviderProfile? get profile => settings?.activeProfile;

  bool get isProviderConfigured => settings?.isConfigured ?? false;

  SkillTranslationState copyWith({
    TranslationSettingsStatus? settingsStatus,
    SkillTranslationPhase? phase,
    Object? settings = _unset,
    Object? request = _unset,
    Object? translatedContent = _unset,
    Object? translatedDescription = _unset,
    Object? failureCode = _unset,
    int? completedBlockCount,
    int? totalBlockCount,
    Map<MarkdownBlockId, String>? translatedBlocks,
    bool? showOriginal,
    TranslationScope? activeScope,
    Map<TranslationScope, CompletedTranslation>? cachedTranslations,
  }) => SkillTranslationState(
    settingsStatus: settingsStatus ?? this.settingsStatus,
    phase: phase ?? this.phase,
    settings: identical(settings, _unset)
        ? this.settings
        : settings as AppTranslationSettings?,
    request: identical(request, _unset)
        ? this.request
        : request as SourceDocument?,
    translatedContent: identical(translatedContent, _unset)
        ? this.translatedContent
        : translatedContent as String?,
    translatedDescription: identical(translatedDescription, _unset)
        ? this.translatedDescription
        : translatedDescription as String?,
    failureCode: identical(failureCode, _unset)
        ? this.failureCode
        : failureCode as String?,
    completedBlockCount: completedBlockCount ?? this.completedBlockCount,
    totalBlockCount: totalBlockCount ?? this.totalBlockCount,
    translatedBlocks: translatedBlocks ?? this.translatedBlocks,
    showOriginal: showOriginal ?? this.showOriginal,
    activeScope: activeScope ?? this.activeScope,
    cachedTranslations: cachedTranslations ?? this.cachedTranslations,
  );
}

const _unset = Object();

final skillTranslationViewModelProvider =
    NotifierProvider<SkillTranslationViewModel, SkillTranslationState>(
      SkillTranslationViewModel.new,
    );

final _appTranslationSettingsProvider = FutureProvider(
  (ref) => ref.watch(appTranslationRepositoryProvider).loadSettings(),
);

typedef SkillDescriptionCacheKey = ({String slotKey, String contentHash});

final cachedSkillDescriptionProvider = FutureProvider.autoDispose
    .family<String?, SkillDescriptionCacheKey>((ref, skill) async {
      final link = ref.keepAlive();
      Timer? releaseTimer;
      ref.onCancel(() {
        releaseTimer = Timer(const Duration(minutes: 5), link.close);
      });
      ref.onResume(() {
        releaseTimer?.cancel();
        releaseTimer = null;
      });
      ref.onDispose(() => releaseTimer?.cancel());
      try {
        final settings = await ref.watch(
          _appTranslationSettingsProvider.future,
        );
        final cache = ref.watch(appTranslationRepositoryProvider);
        final full = await cache.readCachedEntry(
          TranslationCacheKey(
            slotKey: skill.slotKey,
            contentHash: skill.contentHash,
            documentIdentifier: 'SKILL.md',
            targetLanguage: TargetLanguage(
              settings.activeProfile.targetLanguage,
            ),
          ),
        );
        final fullDescription = full == null
            ? null
            : _translatedDescription(full.translatedContent);
        if (fullDescription != null) return fullDescription;
        final description = await cache.readCachedEntry(
          TranslationCacheKey(
            slotKey: skill.slotKey,
            contentHash: skill.contentHash,
            documentIdentifier: 'SKILL.md',
            targetLanguage: TargetLanguage(
              settings.activeProfile.targetLanguage,
            ),
            scope: TranslationScope.descriptionOnly,
          ),
        );
        return description?.translatedContent;
      } on Object {
        link.close();
        rethrow;
      }
    });

final class SkillTranslationViewModel extends Notifier<SkillTranslationState> {
  AppTranslationRepository get _repository =>
      ref.read(appTranslationRepositoryProvider);

  AppNotificationController get _notifications =>
      ref.read(appNotificationControllerProvider.notifier);

  AppTranslationSession? _session;
  StreamSubscription<AppTranslationDraft>? _draftSubscription;
  AppNotificationTaskHandle? _notificationTask;
  var _selectionSequence = 0;
  var _jobSequence = 0;
  String? _fallbackContent;
  String? _fallbackDescription;
  TranslationScope _fallbackScope = TranslationScope.fullDocument;

  @override
  SkillTranslationState build() {
    ref.listen(
      activeTranslationRequestProvider,
      (_, next) => unawaited(_selectRequest(next)),
    );
    ref.onDispose(() {
      _selectionSequence += 1;
      _jobSequence += 1;
      _notificationTask?.dismiss();
      _notificationTask = null;
      unawaited(_session?.cancel());
      unawaited(_draftSubscription?.cancel());
    });
    Future.microtask(() {
      if (!ref.mounted) return;
      unawaited(_selectRequest(ref.read(activeTranslationRequestProvider)));
      unawaited(_loadSettings());
    });
    return const SkillTranslationState();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _repository.loadSettings();
      if (!ref.mounted) return;
      state = state.copyWith(
        settingsStatus: TranslationSettingsStatus.ready,
        settings: settings,
        failureCode: null,
      );
      final request = state.request;
      if (request != null) await _selectRequest(request, force: true);
    } on Object {
      if (!ref.mounted) return;
      state = state.copyWith(
        settingsStatus: TranslationSettingsStatus.failure,
        phase:
            state.request != null &&
                state.phase == SkillTranslationPhase.loadingCache
            ? SkillTranslationPhase.ready
            : state.phase,
        failureCode: 'settings_load_failed',
      );
    }
  }

  Future<void> reloadSettings() => _loadSettings();

  /// Checks an unsaved Provider profile from Settings with a fixed sample.
  Future<AppTranslationConnectionResult> testConnection(
    TranslationProviderProfile profile, {
    String? replacementApiKey,
    bool useStoredCredential = false,
  }) async {
    try {
      return await _repository.testConnection(
        profile: profile,
        replacementApiKey: replacementApiKey,
        useStoredCredential: useStoredCredential,
      );
    } on Object {
      return AppTranslationConnectionResult.failed(
        TranslationFailureCode.unknown.name,
      );
    }
  }

  Future<bool> saveProfile(
    TranslationProviderProfile profile, {
    String? replacementApiKey,
    bool clearCredential = false,
  }) async {
    try {
      final settings = await _repository.saveProfile(
        profile,
        replacementApiKey: replacementApiKey,
        clearCredential: clearCredential,
      );
      if (!ref.mounted) return false;
      state = state.copyWith(
        settingsStatus: TranslationSettingsStatus.ready,
        settings: settings,
        failureCode: null,
      );
      ref.invalidate(_appTranslationSettingsProvider);
      final request = state.request;
      if (request != null) await _selectRequest(request, force: true);
      return true;
    } on FormatException {
      if (!ref.mounted) return false;
      state = state.copyWith(failureCode: 'settings_invalid');
      return false;
    } on Object {
      if (!ref.mounted) return false;
      state = state.copyWith(failureCode: 'settings_save_failed');
      return false;
    }
  }

  Future<bool> clearProfile() async {
    try {
      final settings = await _repository.clearProfile();
      if (!ref.mounted) return false;
      state = state.copyWith(
        settingsStatus: TranslationSettingsStatus.ready,
        settings: settings,
        failureCode: null,
      );
      ref.invalidate(_appTranslationSettingsProvider);
      final request = state.request;
      if (request != null) await _selectRequest(request, force: true);
      return true;
    } on Object {
      if (!ref.mounted) return false;
      state = state.copyWith(failureCode: 'settings_save_failed');
      return false;
    }
  }

  Future<void> _selectRequest(
    SourceDocument? request, {
    bool force = false,
  }) async {
    final current = state.request;
    if (!force && current == request) return;
    final sequence = ++_selectionSequence;
    final cleanup = _cancelActive();
    unawaited(cleanup);
    // Provider dependencies can flush while their consuming Widget is
    // building. Yield once so publishing the new selection never dirties the
    // ProviderScope during that build, without waiting for transport cleanup.
    await Future<void>.value();
    if (!ref.mounted || sequence != _selectionSequence) return;
    state = state.copyWith(
      request: request,
      phase: request == null
          ? SkillTranslationPhase.idle
          : SkillTranslationPhase.loadingCache,
      translatedContent: null,
      translatedDescription: null,
      failureCode: state.settingsStatus == TranslationSettingsStatus.failure
          ? 'settings_load_failed'
          : null,
      completedBlockCount: 0,
      totalBlockCount: 0,
      translatedBlocks: const {},
      showOriginal: false,
      activeScope: TranslationScope.fullDocument,
      cachedTranslations: const {},
    );
    if (request == null) return;
    if (state.settingsStatus == TranslationSettingsStatus.loading) return;
    final profile = state.profile;
    if (profile == null) {
      state = state.copyWith(phase: SkillTranslationPhase.ready);
      return;
    }
    try {
      final full = await _repository.readCached(
        request: request,
        targetLanguage: profile.targetLanguage,
      );
      final description = request.documentIdentifier == 'SKILL.md'
          ? await _repository.readCached(
              request: request,
              targetLanguage: profile.targetLanguage,
              scope: TranslationScope.descriptionOnly,
            )
          : null;
      if (!ref.mounted || sequence != _selectionSequence) return;
      final cached = full ?? description;
      final content = cached?.translatedContent;
      final cachedTranslations = <TranslationScope, CompletedTranslation>{};
      if (full != null) {
        cachedTranslations[TranslationScope.fullDocument] = full;
      }
      if (description != null) {
        cachedTranslations[TranslationScope.descriptionOnly] = description;
      }
      state = state.copyWith(
        phase: SkillTranslationPhase.ready,
        translatedContent: content,
        translatedDescription: content == null
            ? null
            : cached!.scope == TranslationScope.descriptionOnly
            ? content
            : _translatedDescription(content),
        activeScope: cached?.scope ?? TranslationScope.fullDocument,
        cachedTranslations: Map.unmodifiable(cachedTranslations),
      );
    } on Object {
      if (!ref.mounted || sequence != _selectionSequence) return;
      state = state.copyWith(
        phase: SkillTranslationPhase.ready,
        failureCode: 'cache_unavailable',
      );
    }
  }

  void showCachedTranslation(TranslationScope scope) {
    if (state.isBusy) return;
    final cached = state.cachedTranslations[scope];
    if (cached == null) return;
    state = state.copyWith(
      phase: SkillTranslationPhase.ready,
      activeScope: scope,
      translatedContent: cached.translatedContent,
      translatedDescription: scope == TranslationScope.descriptionOnly
          ? cached.translatedContent
          : _translatedDescription(cached.translatedContent),
      translatedBlocks: const {},
      showOriginal: false,
      failureCode: null,
    );
  }

  Future<void> translate([
    TranslationScope scope = TranslationScope.fullDocument,
  ]) async {
    if (!state.canTranslate) return;
    if (scope == TranslationScope.descriptionOnly &&
        !state.canTranslateDescription) {
      return;
    }
    if (!state.isProviderConfigured) {
      _notifications.warning(AppNotificationMessage.translationConfigureFirst);
      return;
    }
    final request = state.request!;
    final profile = state.profile!;
    final sequence = ++_jobSequence;
    _fallbackContent = state.translatedContent;
    _fallbackDescription = state.translatedDescription;
    _fallbackScope = state.activeScope;
    AppTranslationSession session;
    try {
      session = await _repository.start(
        request: request,
        profile: profile,
        scope: scope,
      );
    } on AppTranslationConfigurationException catch (error) {
      if (error.code == 'provider_not_configured') {
        _notifications.warning(
          AppNotificationMessage.translationConfigureFirst,
        );
        return;
      }
      state = state.copyWith(
        phase: SkillTranslationPhase.failed,
        failureCode: error.code,
      );
      _notifications.error(AppNotificationMessage.translationFailed);
      return;
    } on Object {
      state = state.copyWith(
        phase: SkillTranslationPhase.failed,
        failureCode: 'translation_start_failed',
      );
      _notifications.error(AppNotificationMessage.translationFailed);
      return;
    }
    if (!ref.mounted || sequence != _jobSequence) {
      await session.cancel();
      return;
    }
    _session = session;
    state = state.copyWith(
      phase: SkillTranslationPhase.translating,
      translatedContent: null,
      translatedDescription: null,
      failureCode: null,
      completedBlockCount: 0,
      totalBlockCount: 0,
      translatedBlocks: const {},
      showOriginal: false,
      activeScope: scope,
    );
    _notificationTask = _notifications.startTask(
      const AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: AppNotificationMessage.translationStarted,
      ),
    );
    _draftSubscription = session.drafts.listen((draft) {
      if (!ref.mounted || sequence != _jobSequence) return;
      state = state.copyWith(
        translatedDescription: draft.translatedDescription,
        completedBlockCount: draft.completedBlockCount,
        totalBlockCount: draft.totalBlockCount,
        translatedBlocks: draft.translatedBlocks,
      );
      final progress = _notificationProgress(
        completed: draft.completedBlockCount,
        total: draft.totalBlockCount,
      );
      _notificationTask?.update(
        AppNotification.message(
          severity: AppNotificationSeverity.info,
          message: progress == null
              ? AppNotificationMessage.translationStarted
              : AppNotificationMessage.translationProgress,
          progress: progress,
        ),
      );
    });
    TranslationJobOutcome outcome;
    try {
      outcome = await session.result;
    } on Object {
      if (!ref.mounted || sequence != _jobSequence) return;
      _session = null;
      final subscription = _draftSubscription;
      _draftSubscription = null;
      if (subscription != null) {
        try {
          await subscription.cancel();
        } on Object {
          // The Job has already failed. Subscription cleanup must not leak a
          // second implementation error or replace the sanitized app code.
        }
      }
      if (!ref.mounted || sequence != _jobSequence) return;
      _restoreFallback(
        phase: SkillTranslationPhase.failed,
        failureCode: 'translation_cache_write_failed',
      );
      _finishNotificationTask(
        severity: AppNotificationSeverity.error,
        message: AppNotificationMessage.translationFailed,
      );
      return;
    }
    if (!ref.mounted || sequence != _jobSequence) return;
    _session = null;
    _draftSubscription = null;
    switch (outcome) {
      case CompletedTranslation():
        ref.invalidate(
          cachedSkillDescriptionProvider((
            slotKey: outcome.slotKey,
            contentHash: outcome.contentHash,
          )),
        );
        state = state.copyWith(
          phase: SkillTranslationPhase.ready,
          translatedContent: outcome.translatedContent,
          translatedDescription: scope == TranslationScope.descriptionOnly
              ? outcome.translatedContent
              : _translatedDescription(outcome.translatedContent),
          cachedTranslations: {...state.cachedTranslations, scope: outcome},
          failureCode: null,
        );
        _finishNotificationTask(
          severity: AppNotificationSeverity.success,
          message: AppNotificationMessage.translationCompleted,
        );
      case TranslationFailure(
        :final providerErrorCode,
        :final providerErrorMessage,
      ):
        _restoreFallback(
          phase: SkillTranslationPhase.failed,
          failureCode: 'translation_${outcome.code.name}',
        );
        _finishNotificationTask(
          severity: AppNotificationSeverity.error,
          message: AppNotificationMessage.translationFailed,
          providerError: _providerErrorText(
            providerErrorCode,
            providerErrorMessage,
          ),
        );
      case TranslationJobCancellation():
        _restoreFallback(phase: SkillTranslationPhase.cancelled);
        _finishNotificationTask(
          severity: AppNotificationSeverity.info,
          message: AppNotificationMessage.translationCancelled,
        );
    }
  }

  /// Switches the detail page back to the original document without discarding
  /// the cached translation, so a later [translate] or reselection restores it.
  void showOriginalContent() {
    if (!state.showsTranslation) return;
    state = state.copyWith(showOriginal: true);
  }

  /// Deletes every cached translation for the current Skill's Slot and drops
  /// the in-memory translation so the page falls back to the original.
  Future<bool> deleteCachedTranslation() async {
    final request = state.request;
    if (request == null || state.isBusy) return false;
    final deleted = await ref
        .read(appTranslationCacheCleanupProvider)
        .deleteSlot(request.slotKey);
    if (!ref.mounted || !deleted) return deleted;
    state = state.copyWith(
      translatedContent: null,
      translatedDescription: null,
      translatedBlocks: const {},
      showOriginal: false,
      cachedTranslations: const {},
    );
    _fallbackContent = null;
    _fallbackDescription = null;
    ref.invalidate(
      cachedSkillDescriptionProvider((
        slotKey: request.slotKey,
        contentHash: request.contentHash,
      )),
    );
    _notifications.info(AppNotificationMessage.translationCacheDeleted);
    return true;
  }

  Future<void> cancel() async {
    if (_session == null) return;
    state = state.copyWith(phase: SkillTranslationPhase.cancelling);
    _notificationTask?.update(
      AppNotification.message(
        severity: AppNotificationSeverity.info,
        message: AppNotificationMessage.translationCancelling,
        progress: _notificationProgress(
          completed: state.completedBlockCount,
          total: state.totalBlockCount,
        ),
      ),
    );
    await _session?.cancel();
  }

  Future<void> _cancelActive() async {
    final session = _session;
    _session = null;
    _jobSequence += 1;
    final notificationTask = _notificationTask;
    _notificationTask = null;
    notificationTask?.dismiss();
    final subscription = _draftSubscription;
    _draftSubscription = null;
    if (session != null) {
      try {
        await session.cancel();
      } on Object {
        // Selection has already invalidated the Job. Cleanup failures must not
        // block the new document or expose transport details.
      }
    }
    if (subscription != null) {
      try {
        await subscription.cancel();
      } on Object {
        // The detached session can close its Draft stream concurrently.
      }
    }
  }

  void _restoreFallback({
    required SkillTranslationPhase phase,
    String? failureCode,
  }) {
    state = state.copyWith(
      phase: phase,
      translatedContent: _fallbackContent,
      translatedDescription: _fallbackDescription,
      activeScope: _fallbackScope,
      failureCode: failureCode,
      completedBlockCount: 0,
      totalBlockCount: 0,
      translatedBlocks: const {},
    );
  }

  void _finishNotificationTask({
    required AppNotificationSeverity severity,
    required AppNotificationMessage message,
    String? providerError,
  }) {
    final task = _notificationTask;
    _notificationTask = null;
    task?.finish(
      AppNotification.message(
        severity: severity,
        message: message,
        providerError: providerError,
      ),
    );
  }
}

String? _providerErrorText(String? code, String? message) {
  if (code == null && message == null) return null;
  if (code == null) return message;
  if (message == null) return code;
  return '$code: $message';
}

AppNotificationProgress? _notificationProgress({
  required int completed,
  required int total,
}) {
  if (total <= 0) return null;
  return AppNotificationProgress(
    completed: completed.clamp(0, total),
    total: total,
  );
}

String? _translatedDescription(String document) {
  return readTranslatableSkillDescription(document);
}
