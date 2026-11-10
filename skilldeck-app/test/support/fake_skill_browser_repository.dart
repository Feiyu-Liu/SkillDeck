import 'dart:async';

import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

final class FakeSkillBrowserRepository implements SkillBrowserRepository {
  FakeSkillBrowserRepository({
    InstalledSkillCatalog? catalog,
    Map<String, String>? documents,
    Map<String, Map<String, String>>? additionalDocuments,
  }) : catalog =
           catalog ?? InstalledSkillCatalog(revision: 0, skills: const []),
       documents = {...?documents},
       additionalDocuments = {
         for (final entry in (additionalDocuments ?? const {}).entries)
           entry.key: {...entry.value},
       };

  InstalledSkillCatalog catalog;
  final StreamController<InstalledSkillCatalog> _catalogs =
      StreamController<InstalledSkillCatalog>.broadcast();
  final Map<String, String> documents;
  final Map<String, Map<String, String>> additionalDocuments;
  final Map<String, Object> documentErrors = {};
  Future<InstalledSkillCatalog> Function()? openHandler;
  Future<InstalledSkillCatalog> Function()? refreshHandler;
  Future<String> Function(InstalledSkill skill)? readDocumentHandler;
  Future<String> Function(InstalledSkill skill, String relativePath)?
  readDocumentPathHandler;
  Future<List<SkillDocumentEntry>> Function(InstalledSkill skill)?
  listDocumentsHandler;
  int openCalls = 0;
  int refreshCalls = 0;
  int closeCalls = 0;
  final List<String> documentReads = [];
  final List<({String slotKey, String relativePath})> documentPathReads = [];
  final List<String> documentContentHashReads = [];

  @override
  Stream<InstalledSkillCatalog> get catalogs => _catalogs.stream;

  void publish(InstalledSkillCatalog value) {
    catalog = value;
    _catalogs.add(value);
  }

  @override
  Future<WorkspaceCompletion<InstalledSkillCatalog>> open() async {
    openCalls += 1;
    return _completion(() async => openHandler?.call() ?? catalog);
  }

  @override
  Future<WorkspaceCompletion<InstalledSkillCatalog>> refresh() async {
    refreshCalls += 1;
    return _completion(() async => refreshHandler?.call() ?? catalog);
  }

  @override
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listDocuments(
    InstalledSkill skill,
  ) => _completion(() async {
    final handler = listDocumentsHandler;
    if (handler != null) return handler(skill);
    return List.unmodifiable(<SkillDocumentEntry>[
      if (documents.containsKey(skill.slotKey))
        SkillDocumentEntry(
          relativePath: 'SKILL.md',
          name: 'SKILL.md',
          contentHash: skill.contentHash,
        ),
      for (final path
          in additionalDocuments[skill.slotKey]?.keys ?? const <String>[])
        SkillDocumentEntry(
          relativePath: path,
          name: path.split('/').last,
          contentHash: skill.contentHash,
        ),
    ]);
  });

  @override
  Future<WorkspaceCompletion<String>> readDocument(
    InstalledSkill skill,
    String relativePath, {
    required String expectedContentHash,
  }) => _completion(() async {
    documentReads.add(skill.slotKey);
    documentPathReads.add((slotKey: skill.slotKey, relativePath: relativePath));
    documentContentHashReads.add(expectedContentHash);
    final pathHandler = readDocumentPathHandler;
    if (pathHandler != null) return pathHandler(skill, relativePath);
    final handler = readDocumentHandler;
    if (handler != null) return handler(skill);
    final error = documentErrors[skill.slotKey];
    if (error != null) throw error;
    final document = relativePath == 'SKILL.md'
        ? documents[skill.slotKey]
        : additionalDocuments[skill.slotKey]?[relativePath];
    if (document == null) {
      throw WorkspaceException(
        code: WorkspaceErrorCode.documentUnavailable,
        operation: WorkspaceOperationKind.readDocument,
      );
    }
    return document;
  });

  Future<WorkspaceCompletion<T>> _completion<T>(
    Future<T> Function() read,
  ) async {
    try {
      return WorkspaceCompleted(value: await read());
    } on WorkspaceFailure catch (failure) {
      return WorkspaceFailed(failure: failure, warnings: failure.warnings);
    }
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
    await _catalogs.close();
  }
}

/// The ordinary fixture Skill: installed and reachable from the Global Scope.
/// Tests about the inactive bucket leave `activations` empty instead.
List<SkillActivationLocation> globalActivation({
  String location = '/global/skills',
  List<String> agentIds = const ['claude'],
}) => [
  SkillActivationLocation(
    location: location,
    scope: WorkspaceScope.global,
    mode: WorkspaceActivationMode.symbolicLink,
    agentIds: agentIds,
  ),
];

InstalledSkill testSkill({
  required String slotKey,
  required String displayName,
  WorkspaceSkillId? id,
  String? contentHash,
  int activationCount = 0,
  List<SkillActivationLocation> activations = const [],
  bool isFavorite = false,
  String? note,
}) => InstalledSkill(
  id: id ?? WorkspaceSkillId(slotKey),
  slotKey: slotKey,
  displayName: displayName,
  description: '$displayName description',
  contentHash: contentHash ?? List.filled(64, 'a').join(),
  activationCount: activations.isEmpty ? activationCount : activations.length,
  activations: activations,
  isFavorite: isFavorite,
  note: note,
);
