import 'dart:async';

import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/translation/presentation/view_models/skill_translation_view_model.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/platform/platform_providers.dart';

enum CatalogStatus { loading, ready, failure, unsupported }

enum DocumentStatus { none, loading, ready, failure }

enum DocumentCatalogStatus { none, loading, ready, failure }

const _stateUnset = Object();

final skillBrowserViewModelProvider =
    NotifierProvider<SkillBrowserViewModel, SkillBrowserState>(
      SkillBrowserViewModel.new,
    );

enum SkillBrowserCatalogAuthority { workspaceSnapshot, repository }

/// Selects the explicit catalog authority for a composition.
///
/// Production uses the root Workspace Snapshot. Isolated widget tests may
/// override this with [SkillBrowserCatalogAuthority.repository] to drive the
/// existing browser fake without coupling presentation code to its concrete
/// implementation type.
final skillBrowserCatalogAuthorityProvider = Provider(
  (ref) => SkillBrowserCatalogAuthority.workspaceSnapshot,
);

/// The catalog projection rendered by Installed/Favorites and Skill routes.
///
/// Production reads the root Workspace Snapshot directly. Repository-backed
/// catalogs are an explicit test/embedding composition choice rather than a
/// runtime type check.
final skillBrowserCatalogProvider = Provider<SkillBrowserCatalogState>((ref) {
  final local = ref.watch(skillBrowserViewModelProvider);
  final authority = ref.watch(skillBrowserCatalogAuthorityProvider);
  if (authority == SkillBrowserCatalogAuthority.repository) {
    return SkillBrowserCatalogState.fromLegacy(local);
  }
  if (!ref.watch(desktopSupportedProvider)) {
    return SkillBrowserCatalogState(
      status: CatalogStatus.unsupported,
      refreshing: local.refreshing,
      refreshFailure: local.refreshFailure,
    );
  }
  return ref
      .watch(workspaceInstalledSkillCatalogProvider)
      .when(
        data: (catalog) => SkillBrowserCatalogState(
          status: CatalogStatus.ready,
          skills: catalog.skills,
          projectRoots: catalog.projectRoots,
          revision: catalog.revision,
          refreshing: local.refreshing,
          refreshFailure: local.refreshFailure,
        ),
        error: (error, stackTrace) => SkillBrowserCatalogState(
          status: CatalogStatus.failure,
          failure: ref
              .read(appFailureReporterProvider)
              .capture(
                error,
                stackTrace,
                operationKey: 'openRepository',
                message: AppFailureMessage.repositoryOpen,
              ),
          refreshing: local.refreshing,
          refreshFailure: local.refreshFailure,
        ),
        loading: () => SkillBrowserCatalogState(
          status: CatalogStatus.loading,
          refreshing: local.refreshing,
          refreshFailure: local.refreshFailure,
        ),
      );
});

/// Preloads every catalog description so scrolling never touches the cache.
final skillDescriptionPreloadProvider = Provider.autoDispose<void>((ref) {
  final catalog = ref.watch(skillBrowserCatalogProvider);
  if (catalog.status != CatalogStatus.ready) return;
  for (final skill in catalog.skills) {
    ref.watch(
      cachedSkillDescriptionProvider((
        slotKey: skill.slotKey,
        contentHash: skill.contentHash,
      )),
    );
  }
});

final skillSearchQueryProvider = NotifierProvider<SkillSearchQuery, String>(
  SkillSearchQuery.new,
);

final workspaceUiProvider =
    NotifierProvider<WorkspaceUiController, WorkspaceUiState>(
      WorkspaceUiController.new,
    );

final class SkillBrowserCatalogState {
  SkillBrowserCatalogState({
    required this.status,
    List<InstalledSkill> skills = const [],
    List<SkillProjectRoot> projectRoots = const [],
    this.revision = 0,
    this.failure,
    this.refreshFailure,
    this.refreshing = false,
  }) : skills = List.unmodifiable(skills),
       projectRoots = List.unmodifiable(projectRoots);

  factory SkillBrowserCatalogState.fromLegacy(SkillBrowserState state) =>
      SkillBrowserCatalogState(
        status: state.catalogStatus,
        skills: state.skills,
        projectRoots: state.projectRoots,
        revision: state.revision,
        failure: state.catalogFailure,
        refreshFailure: state.refreshFailure,
        refreshing: state.refreshing,
      );

  final CatalogStatus status;
  final List<InstalledSkill> skills;
  final List<SkillProjectRoot> projectRoots;
  final int revision;
  final AppFailure? failure;
  final AppFailure? refreshFailure;
  final bool refreshing;
}

final installedScopeFilterProvider =
    NotifierProvider<InstalledScopeFilterController, InstalledScopeFilter>(
      InstalledScopeFilterController.new,
    );

final installedProjectRootFilterProvider =
    NotifierProvider<InstalledProjectRootFilterController, String?>(
      InstalledProjectRootFilterController.new,
    );

final installedLocationFilterProvider =
    NotifierProvider<
      InstalledLocationFilterController,
      InstalledLocationFilter
    >(InstalledLocationFilterController.new);

final class SkillBrowserState {
  const SkillBrowserState({
    this.catalogStatus = CatalogStatus.loading,
    this.documentStatus = DocumentStatus.none,
    this.documentCatalogStatus = DocumentCatalogStatus.none,
    this.skills = const [],
    this.documents = const [],
    this.projectRoots = const [],
    this.revision = 0,
    this.catalogFailure,
    this.refreshFailure,
    this.selectedSkill,
    this.document,
    this.documentFailure,
    this.documentCatalogFailure,
    this.selectedDocumentPath,
    this.documentContentHash,
    this.refreshing = false,
  });

  final CatalogStatus catalogStatus;
  final DocumentStatus documentStatus;
  final DocumentCatalogStatus documentCatalogStatus;
  final List<InstalledSkill> skills;
  final List<SkillDocumentEntry> documents;
  final List<SkillProjectRoot> projectRoots;
  final int revision;
  final AppFailure? catalogFailure;
  final AppFailure? refreshFailure;
  final InstalledSkill? selectedSkill;
  final String? document;
  final AppFailure? documentFailure;
  final AppFailure? documentCatalogFailure;
  final String? selectedDocumentPath;
  final String? documentContentHash;
  final bool refreshing;

  SkillBrowserState copyWith({
    CatalogStatus? catalogStatus,
    DocumentStatus? documentStatus,
    DocumentCatalogStatus? documentCatalogStatus,
    List<InstalledSkill>? skills,
    List<SkillDocumentEntry>? documents,
    List<SkillProjectRoot>? projectRoots,
    int? revision,
    Object? catalogFailure = _stateUnset,
    Object? refreshFailure = _stateUnset,
    Object? selectedSkill = _stateUnset,
    Object? document = _stateUnset,
    Object? documentFailure = _stateUnset,
    Object? documentCatalogFailure = _stateUnset,
    Object? selectedDocumentPath = _stateUnset,
    Object? documentContentHash = _stateUnset,
    bool? refreshing,
  }) => SkillBrowserState(
    catalogStatus: catalogStatus ?? this.catalogStatus,
    documentStatus: documentStatus ?? this.documentStatus,
    documentCatalogStatus: documentCatalogStatus ?? this.documentCatalogStatus,
    skills: skills ?? this.skills,
    documents: documents ?? this.documents,
    projectRoots: projectRoots ?? this.projectRoots,
    revision: revision ?? this.revision,
    catalogFailure: identical(catalogFailure, _stateUnset)
        ? this.catalogFailure
        : catalogFailure as AppFailure?,
    refreshFailure: identical(refreshFailure, _stateUnset)
        ? this.refreshFailure
        : refreshFailure as AppFailure?,
    selectedSkill: identical(selectedSkill, _stateUnset)
        ? this.selectedSkill
        : selectedSkill as InstalledSkill?,
    document: identical(document, _stateUnset)
        ? this.document
        : document as String?,
    documentFailure: identical(documentFailure, _stateUnset)
        ? this.documentFailure
        : documentFailure as AppFailure?,
    documentCatalogFailure: identical(documentCatalogFailure, _stateUnset)
        ? this.documentCatalogFailure
        : documentCatalogFailure as AppFailure?,
    selectedDocumentPath: identical(selectedDocumentPath, _stateUnset)
        ? this.selectedDocumentPath
        : selectedDocumentPath as String?,
    documentContentHash: identical(documentContentHash, _stateUnset)
        ? this.documentContentHash
        : documentContentHash as String?,
    refreshing: refreshing ?? this.refreshing,
  );
}

final class SkillBrowserViewModel extends Notifier<SkillBrowserState> {
  var _loading = false;
  var _refreshing = false;
  var _documentRequest = 0;
  var _documentCatalogRequest = 0;
  var _workspaceSelectionRequest = 0;
  Future<void>? _workspaceSelectionFuture;
  WorkspaceSkillId? _loadingSelectionId;
  StreamSubscription<InstalledSkillCatalog>? _catalogSubscription;

  SkillBrowserRepository get _repository =>
      ref.read(skillBrowserRepositoryProvider);

  bool get _desktopSupported => ref.read(desktopSupportedProvider);

  CatalogStatus get catalogStatus => state.catalogStatus;
  DocumentStatus get documentStatus => state.documentStatus;
  DocumentCatalogStatus get documentCatalogStatus =>
      state.documentCatalogStatus;
  List<InstalledSkill> get skills => state.skills;
  List<SkillDocumentEntry> get documents => state.documents;
  int get revision => state.revision;
  AppFailure? get catalogFailure => state.catalogFailure;
  AppFailure? get refreshFailure => state.refreshFailure;
  InstalledSkill? get selectedSkill => state.selectedSkill;
  String? get document => state.document;
  AppFailure? get documentFailure => state.documentFailure;
  AppFailure? get documentCatalogFailure => state.documentCatalogFailure;
  String? get selectedDocumentPath => state.selectedDocumentPath;
  String? get documentContentHash => state.documentContentHash;
  bool get refreshing => state.refreshing;

  @override
  SkillBrowserState build() {
    if (_usesWorkspaceSnapshot) {
      ref.listen(workspaceInstalledSkillCatalogProvider, (previous, next) {
        next.whenData((catalog) {
          // A widget read can lazily flush this catalog during build. Defer
          // selection/filter mutations, and discard superseded notifications.
          final request = ++_workspaceSelectionRequest;
          _documentRequest += 1;
          _documentCatalogRequest += 1;
          _workspaceSelectionFuture = Future<void>.microtask(() async {
            if (!ref.mounted || request != _workspaceSelectionRequest) return;
            await _reconcileWorkspaceSelection(catalog);
          });
        });
      }, fireImmediately: true);
    } else {
      _catalogSubscription = _repository.catalogs.listen((catalog) {
        if (ref.mounted) {
          unawaited(_applyCatalog(catalog, preserveSelection: true));
        }
      });
    }
    ref.onDispose(() {
      _workspaceSelectionRequest += 1;
      _documentRequest += 1;
      _documentCatalogRequest += 1;
      unawaited(_catalogSubscription?.cancel());
    });
    return const SkillBrowserState();
  }

  Future<void> load() async {
    if (_loading) return;
    if (!_desktopSupported) {
      state = state.copyWith(
        catalogStatus: CatalogStatus.unsupported,
        catalogFailure: null,
      );
      return;
    }
    if (_usesWorkspaceSnapshot) {
      try {
        await ref.read(workspaceSnapshotProvider.future);
        ref.read(workspaceInstalledSkillCatalogProvider);
        await _workspaceSelectionFuture;
      } on Object {
        // The root Snapshot listener already captures the typed failure.
      }
      return;
    }
    _loading = true;
    state = state.copyWith(
      catalogStatus: CatalogStatus.loading,
      catalogFailure: null,
    );
    try {
      final completion = await _repository.open();
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted(:final value):
          await _applyCatalog(value, preserveSelection: false);
        case WorkspaceFailed(:final failure):
          _setCatalogFailure(failure);
        case WorkspaceCommittedPending(:final operationId):
          throw StateError(
            'Read-only browser open $operationId cannot require finalization.',
          );
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      state = state.copyWith(
        catalogStatus: CatalogStatus.failure,
        catalogFailure: ref
            .read(appFailureReporterProvider)
            .capture(
              error,
              stackTrace,
              operationKey: 'openRepository',
              message: AppFailureMessage.repositoryOpen,
            ),
      );
    } finally {
      _loading = false;
    }
  }

  Future<void> refresh() async {
    if (_refreshing || _catalogStatus != CatalogStatus.ready) return;
    _refreshing = true;
    ref.read(activationCatalogRevisionProvider.notifier).refresh();
    state = state.copyWith(refreshing: true, refreshFailure: null);
    try {
      final completion = await _repository.refresh();
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted(:final value):
          if (!_usesWorkspaceSnapshot) {
            await _applyCatalog(value, preserveSelection: true);
          }
        case WorkspaceFailed(:final failure):
          _setRefreshFailure(failure);
          return;
        case WorkspaceCommittedPending(:final operationId):
          throw StateError(
            'Read-only browser refresh $operationId cannot require finalization.',
          );
      }
      if (!ref.mounted) return;
      ref
          .read(appNotificationControllerProvider.notifier)
          .success(AppNotificationMessage.repositoryRefreshed);
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      final failure = ref
          .read(appFailureReporterProvider)
          .capture(
            error,
            stackTrace,
            operationKey: 'refreshRepository',
            message: AppFailureMessage.repositoryRefresh,
          );
      state = state.copyWith(refreshing: false, refreshFailure: failure);
      ref
          .read(appNotificationControllerProvider.notifier)
          .publish(AppNotification.failure(failure));
    } finally {
      _refreshing = false;
      if (ref.mounted && state.refreshing) {
        state = state.copyWith(refreshing: false);
      }
    }
  }

  Future<bool> selectSkill(WorkspaceSkillId skillId) async {
    final selected = _skillFor(skillId);
    if (selected == null) return false;
    if (_loadingSelectionId == skillId) return true;
    return _loadSkillDocuments(selected);
  }

  Future<void> selectDocument(String relativePath) async {
    final selected = _selectedSkill;
    if (selected == null ||
        !state.documents.any(
          (document) => document.relativePath == relativePath,
        )) {
      return;
    }
    if (state.selectedDocumentPath == relativePath &&
        state.documentStatus == DocumentStatus.ready) {
      return;
    }
    final document = state.documents.firstWhere(
      (entry) => entry.relativePath == relativePath,
    );
    await _loadDocument(selected, document);
  }

  Future<bool> _loadSkillDocuments(
    InstalledSkill selected, {
    String? preferredDocumentPath,
  }) async {
    _loadingSelectionId = selected.id;
    _documentRequest += 1;
    state = state.copyWith(
      selectedSkill: selected,
      documents: const [],
      documentCatalogFailure: null,
      documentCatalogStatus: DocumentCatalogStatus.loading,
      selectedDocumentPath: 'SKILL.md',
      documentContentHash: null,
      document: null,
      documentFailure: null,
      documentStatus: DocumentStatus.loading,
    );
    final catalogRequest = ++_documentCatalogRequest;
    var selectedPath = 'SKILL.md';
    SkillDocumentEntry? selectedDocument;
    try {
      final completion = await _repository.listDocuments(selected);
      if (!ref.mounted || catalogRequest != _documentCatalogRequest) {
        _finishSkillLoad(selected, catalogRequest);
        return true;
      }
      List<SkillDocumentEntry>? documents;
      switch (completion) {
        case WorkspaceCompleted(:final value):
          documents = value;
        case WorkspaceFailed(:final failure):
          _setDocumentCatalogFailure(failure);
        case WorkspaceCommittedPending(:final operationId):
          throw StateError(
            'Document listing $operationId cannot require finalization.',
          );
      }
      if (documents case final listedDocuments?) {
        if (preferredDocumentPath != null &&
            listedDocuments.any(
              (document) => document.relativePath == preferredDocumentPath,
            )) {
          selectedPath = preferredDocumentPath;
        }
        state = state.copyWith(
          documents: List.unmodifiable(listedDocuments),
          documentCatalogFailure: null,
          documentCatalogStatus: DocumentCatalogStatus.ready,
          selectedDocumentPath: selectedPath,
        );
        if (listedDocuments.isNotEmpty) {
          final fallbackDocument = listedDocuments.first;
          selectedDocument = listedDocuments.firstWhere(
            (document) => document.relativePath == selectedPath,
            orElse: () => fallbackDocument,
          );
          selectedPath = selectedDocument.relativePath;
          state = state.copyWith(selectedDocumentPath: selectedPath);
        }
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted || catalogRequest != _documentCatalogRequest) {
        _finishSkillLoad(selected, catalogRequest);
        return true;
      }
      state = state.copyWith(
        documentCatalogFailure: ref
            .read(appFailureReporterProvider)
            .capture(
              error,
              stackTrace,
              operationKey: 'listDocuments',
              message: AppFailureMessage.documentRead,
              recoveryPolicy: AppRecoveryPolicy.refresh,
            ),
        documentCatalogStatus: DocumentCatalogStatus.failure,
      );
    }
    if (ref.mounted && catalogRequest == _documentCatalogRequest) {
      await _loadDocument(
        selected,
        selectedDocument ??
            SkillDocumentEntry(
              relativePath: selectedPath,
              name: selectedPath.split('/').last,
              contentHash: selected.contentHash,
            ),
      );
    }
    _finishSkillLoad(selected, catalogRequest);
    return true;
  }

  void _finishSkillLoad(InstalledSkill selected, int catalogRequest) {
    if (catalogRequest == _documentCatalogRequest &&
        _loadingSelectionId == selected.id) {
      _loadingSelectionId = null;
    }
  }

  Future<void> retryDocument() async {
    final selected = _selectedSkill;
    final relativePath = state.selectedDocumentPath;
    final contentHash = state.documentContentHash;
    if (selected != null && relativePath != null && contentHash != null) {
      await _loadDocument(
        selected,
        SkillDocumentEntry(
          relativePath: relativePath,
          name: relativePath.split('/').last,
          contentHash: contentHash,
        ),
      );
    }
  }

  Future<void> retryDocumentCatalog() async {
    final selected = _selectedSkill;
    if (selected == null) return;
    final preferred = state.selectedDocumentPath;
    await _loadSkillDocuments(selected, preferredDocumentPath: preferred);
  }

  Future<void> _loadDocument(
    InstalledSkill selected,
    SkillDocumentEntry document,
  ) async {
    state = state.copyWith(
      selectedDocumentPath: document.relativePath,
      documentContentHash: document.contentHash,
      document: null,
      documentFailure: null,
      documentStatus: DocumentStatus.loading,
    );
    final request = ++_documentRequest;
    try {
      final completion = await _repository.readDocument(
        selected,
        document.relativePath,
        expectedContentHash: document.contentHash,
      );
      if (!ref.mounted || request != _documentRequest) return;
      switch (completion) {
        case WorkspaceCompleted(:final value):
          state = state.copyWith(
            document: value,
            documentStatus: DocumentStatus.ready,
          );
        case WorkspaceFailed(:final failure):
          _setDocumentFailure(failure);
        case WorkspaceCommittedPending(:final operationId):
          throw StateError(
            'Document read $operationId cannot require finalization.',
          );
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted || request != _documentRequest) return;
      state = state.copyWith(
        documentFailure: ref
            .read(appFailureReporterProvider)
            .capture(
              error,
              stackTrace,
              operationKey: 'readDocument',
              message: AppFailureMessage.documentRead,
              recoveryPolicy: AppRecoveryPolicy.refresh,
            ),
        documentStatus: DocumentStatus.failure,
      );
    }
  }

  void clearRefreshFailure() {
    if (state.refreshFailure == null) return;
    state = state.copyWith(refreshFailure: null);
  }

  Future<void> _applyCatalog(
    InstalledSkillCatalog catalog, {
    required bool preserveSelection,
  }) async {
    if (state.catalogStatus == CatalogStatus.ready &&
        state.revision == catalog.revision) {
      return;
    }
    final previous = preserveSelection ? state.selectedSkill : null;
    state = state.copyWith(
      skills: List<InstalledSkill>.unmodifiable(catalog.skills),
      projectRoots: List<SkillProjectRoot>.unmodifiable(catalog.projectRoots),
      revision: catalog.revision,
      catalogStatus: CatalogStatus.ready,
      catalogFailure: null,
      refreshFailure: null,
      refreshing: false,
    );
    _reconcileInstalledFilters(catalog);

    InstalledSkill? nextSelection;
    if (previous != null) {
      nextSelection = _skillFor(previous.id);
    }
    nextSelection ??= state.skills.isEmpty ? null : state.skills.first;

    if (nextSelection == null) {
      _documentRequest += 1;
      _documentCatalogRequest += 1;
      state = state.copyWith(
        selectedSkill: null,
        documents: const [],
        documentCatalogFailure: null,
        documentCatalogStatus: DocumentCatalogStatus.none,
        selectedDocumentPath: null,
        documentContentHash: null,
        document: null,
        documentFailure: null,
        documentStatus: DocumentStatus.none,
      );
      return;
    }

    final canPreserveDocument =
        previous != null &&
        previous.id == nextSelection.id &&
        previous.contentHash == nextSelection.contentHash &&
        state.documentStatus == DocumentStatus.ready &&
        state.documentCatalogStatus == DocumentCatalogStatus.ready;
    if (canPreserveDocument) {
      state = state.copyWith(selectedSkill: nextSelection);
    } else {
      await _loadSkillDocuments(
        nextSelection,
        preferredDocumentPath: previous?.id == nextSelection.id
            ? state.selectedDocumentPath
            : null,
      );
    }
  }

  Future<void> _reconcileWorkspaceSelection(
    InstalledSkillCatalog catalog,
  ) async {
    _reconcileInstalledFilters(catalog);
    final previous = state.selectedSkill;
    InstalledSkill? nextSelection;
    if (previous != null) {
      nextSelection = _skillForIn(catalog.skills, previous.id);
    }
    nextSelection ??= catalog.skills.firstOrNull;
    if (nextSelection == null) {
      _clearDocumentSelection();
      return;
    }

    final canPreserveDocument =
        previous != null &&
        previous.id == nextSelection.id &&
        previous.contentHash == nextSelection.contentHash &&
        state.documentStatus == DocumentStatus.ready &&
        state.documentCatalogStatus == DocumentCatalogStatus.ready;
    if (canPreserveDocument) {
      state = state.copyWith(selectedSkill: nextSelection);
      return;
    }
    await _loadSkillDocuments(
      nextSelection,
      preferredDocumentPath: previous?.id == nextSelection.id
          ? state.selectedDocumentPath
          : null,
    );
  }

  void _reconcileInstalledFilters(InstalledSkillCatalog catalog) {
    var scope = ref.read(installedScopeFilterProvider);
    var projectRootId = ref.read(installedProjectRootFilterProvider);
    if (scope == InstalledScopeFilter.project &&
        !catalog.projectRoots.any((root) => root.id == projectRootId)) {
      ref
          .read(installedScopeFilterProvider.notifier)
          .select(InstalledScopeFilter.global);
      ref.read(installedProjectRootFilterProvider.notifier).select(null);
      scope = InstalledScopeFilter.global;
      projectRootId = null;
    }

    final selectedLocation = ref.read(installedLocationFilterProvider);
    if (scope == InstalledScopeFilter.inactive) return;
    if (selectedLocation.kind != InstalledLocationFilterKind.location) return;
    final stillAvailable = catalog.skills.any(
      (skill) => skill.activations.any(
        (activation) =>
            switch (scope) {
              InstalledScopeFilter.global =>
                activation.scope == WorkspaceScope.global,
              InstalledScopeFilter.project =>
                activation.scope == WorkspaceScope.project &&
                    activation.projectRootId == projectRootId,
              InstalledScopeFilter.inactive => false,
            } &&
            activationLocationKey(
                  activation.scope,
                  activation.projectRootId,
                  activation.location,
                ) ==
                selectedLocation.key,
      ),
    );
    if (!stillAvailable) {
      ref
          .read(installedLocationFilterProvider.notifier)
          .select(const InstalledLocationFilter.all());
    }
  }

  void _clearDocumentSelection() {
    _documentRequest += 1;
    _documentCatalogRequest += 1;
    state = state.copyWith(
      selectedSkill: null,
      documents: const [],
      documentCatalogFailure: null,
      documentCatalogStatus: DocumentCatalogStatus.none,
      selectedDocumentPath: null,
      documentContentHash: null,
      document: null,
      documentFailure: null,
      documentStatus: DocumentStatus.none,
    );
  }

  bool get _usesWorkspaceSnapshot =>
      ref.read(skillBrowserCatalogAuthorityProvider) ==
      SkillBrowserCatalogAuthority.workspaceSnapshot;

  CatalogStatus get _catalogStatus {
    if (!_usesWorkspaceSnapshot) return state.catalogStatus;

    // Read the Workspace Snapshot directly. `skillBrowserCatalogProvider`
    // watches this ViewModel for transient refresh state, so reading it here
    // would create a reverse dependency while the catalog is being rebuilt.
    return ref
        .read(workspaceSnapshotProvider)
        .when(
          data: (_) => CatalogStatus.ready,
          loading: () => CatalogStatus.loading,
          error: (_, _) => CatalogStatus.failure,
        );
  }

  InstalledSkill? get _selectedSkill {
    final selected = state.selectedSkill;
    if (selected == null) return null;
    return _skillFor(selected.id);
  }

  List<InstalledSkill> get _currentSkills => _usesWorkspaceSnapshot
      ? ref.read(workspaceInstalledSkillCatalogProvider).value?.skills ??
            const []
      : state.skills;

  void _setCatalogFailure(WorkspaceFailure failure) {
    state = state.copyWith(
      catalogStatus: CatalogStatus.failure,
      catalogFailure: _captureFailure(
        failure,
        operationKey: 'openRepository',
        message: AppFailureMessage.repositoryOpen,
      ),
    );
  }

  void _setRefreshFailure(WorkspaceFailure failure) {
    final appFailure = _captureFailure(
      failure,
      operationKey: 'refreshRepository',
      message: AppFailureMessage.repositoryRefresh,
    );
    state = state.copyWith(refreshing: false, refreshFailure: appFailure);
    ref
        .read(appNotificationControllerProvider.notifier)
        .publish(AppNotification.failure(appFailure));
  }

  void _setDocumentCatalogFailure(WorkspaceFailure failure) {
    state = state.copyWith(
      documentCatalogFailure: _captureFailure(
        failure,
        operationKey: 'listDocuments',
        message: AppFailureMessage.documentRead,
        recoveryPolicy: AppRecoveryPolicy.refresh,
      ),
      documentCatalogStatus: DocumentCatalogStatus.failure,
    );
  }

  void _setDocumentFailure(WorkspaceFailure failure) {
    state = state.copyWith(
      documentFailure: _captureFailure(
        failure,
        operationKey: 'readDocument',
        message: AppFailureMessage.documentRead,
        recoveryPolicy: AppRecoveryPolicy.refresh,
      ),
      documentStatus: DocumentStatus.failure,
    );
  }

  AppFailure _captureFailure(
    WorkspaceFailure failure, {
    required String operationKey,
    required AppFailureMessage message,
    AppRecoveryPolicy recoveryPolicy = AppRecoveryPolicy.retryExplicitly,
  }) => ref
      .read(appFailureReporterProvider)
      .capture(
        failure,
        StackTrace.current,
        operationKey: operationKey,
        message: message,
        recoveryPolicy: recoveryPolicy,
      );

  InstalledSkill? _skillFor(WorkspaceSkillId skillId) {
    return _skillForIn(_currentSkills, skillId);
  }

  InstalledSkill? _skillForIn(
    Iterable<InstalledSkill> skills,
    WorkspaceSkillId skillId,
  ) {
    for (final skill in skills) {
      if (skill.id == skillId) return skill;
    }
    return null;
  }
}

final class SkillSearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final class InstalledScopeFilterController
    extends Notifier<InstalledScopeFilter> {
  @override
  InstalledScopeFilter build() => InstalledScopeFilter.global;

  void select(InstalledScopeFilter value) {
    ref
        .read(installedLocationFilterProvider.notifier)
        .select(const InstalledLocationFilter.all());
    state = value;
  }
}

final class InstalledLocationFilterController
    extends Notifier<InstalledLocationFilter> {
  @override
  InstalledLocationFilter build() => const InstalledLocationFilter.all();

  void select(InstalledLocationFilter value) => state = value;
}

final class InstalledProjectRootFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? value) {
    ref
        .read(installedLocationFilterProvider.notifier)
        .select(const InstalledLocationFilter.all());
    state = value;
  }
}

enum WorkspaceTab { preview, settings }

final class WorkspaceSkillUiState {
  const WorkspaceSkillUiState({
    this.tab = WorkspaceTab.preview,
    this.agentToggles = const {
      'claude': true,
      'cursor': true,
      'windsurf': false,
    },
  });

  final WorkspaceTab tab;
  final Map<String, bool> agentToggles;

  WorkspaceSkillUiState copyWith({
    WorkspaceTab? tab,
    Map<String, bool>? agentToggles,
  }) => WorkspaceSkillUiState(
    tab: tab ?? this.tab,
    agentToggles: agentToggles ?? this.agentToggles,
  );
}

final class WorkspaceUiState {
  const WorkspaceUiState({this.bySkillId = const {}});

  final Map<WorkspaceSkillId, WorkspaceSkillUiState> bySkillId;

  WorkspaceSkillUiState forSkill(WorkspaceSkillId skillId) =>
      bySkillId[skillId] ?? const WorkspaceSkillUiState();
}

final class WorkspaceUiController extends Notifier<WorkspaceUiState> {
  @override
  WorkspaceUiState build() => const WorkspaceUiState();

  void selectTab(WorkspaceSkillId skillId, WorkspaceTab tab) {
    final current = state.forSkill(skillId);
    _replace(skillId, current.copyWith(tab: tab));
  }

  void toggleAgent(WorkspaceSkillId skillId, String agentId, bool value) {
    final current = state.forSkill(skillId);
    _replace(
      skillId,
      current.copyWith(
        agentToggles: Map<String, bool>.unmodifiable({
          ...current.agentToggles,
          agentId: value,
        }),
      ),
    );
  }

  void _replace(WorkspaceSkillId skillId, WorkspaceSkillUiState next) {
    state = WorkspaceUiState(
      bySkillId: Map<WorkspaceSkillId, WorkspaceSkillUiState>.unmodifiable({
        ...state.bySkillId,
        skillId: next,
      }),
    );
  }
}
