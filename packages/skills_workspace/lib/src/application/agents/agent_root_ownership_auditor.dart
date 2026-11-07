import 'package:path/path.dart' as path;

import '../../domain/public_models.dart';
import '../ports/agent_root_ownership_ports.dart';
import 'agent_catalog_controller.dart';

final class AgentRootOwnershipAuditor {
  AgentRootOwnershipAuditor({
    required AgentCatalogController catalogs,
    required AgentRootOwnershipInspectionPort inspection,
    required String userHomePath,
  }) : _catalogs = catalogs,
       _inspection = inspection,
       _userHomePath = path.normalize(path.absolute(userHomePath));

  final AgentCatalogController _catalogs;
  final AgentRootOwnershipInspectionPort _inspection;
  final String _userHomePath;

  Future<AgentRootOwnershipAudit> inspect() async {
    if (!_inspection.supported) {
      return AgentRootOwnershipAudit(
        supported: false,
        examinedRootCount: 0,
        issues: const <AgentRootOwnershipIssue>[],
      );
    }

    final currentUserId = _inspection.currentUserId();
    final physicalHome = await _inspection.physicalDirectoryPath(_userHomePath);
    final configured = _configuredRoots();
    final inspectedByPhysicalPath = <String, _InspectedRoot>{};

    for (final root in configured.values) {
      AgentRootEntryMetadata? rootMetadata;
      try {
        rootMetadata = await _inspection.inspect(root.path);
      } on Object {
        _mergeIssue(
          inspectedByPhysicalPath,
          root.path,
          root,
          AgentRootOwnershipIssueReason.inspectionFailed,
          repairable: false,
        );
        continue;
      }
      if (rootMetadata == null) continue;
      // A linked root, canonical or compatibility, is audited and repaired at
      // the directory it resolves to.
      if (rootMetadata.type != AgentRootEntryType.symbolicLink &&
          rootMetadata.type != AgentRootEntryType.directory) {
        _mergeIssue(
          inspectedByPhysicalPath,
          root.path,
          root,
          AgentRootOwnershipIssueReason.notDirectory,
          repairable: false,
        );
        continue;
      }

      String physicalRoot;
      try {
        physicalRoot = await _inspection.physicalDirectoryPath(root.path);
      } on Object {
        _mergeIssue(
          inspectedByPhysicalPath,
          root.path,
          root,
          AgentRootOwnershipIssueReason.inspectionFailed,
          repairable: false,
        );
        continue;
      }
      if (!path.isWithin(physicalHome, physicalRoot)) {
        _mergeIssue(
          inspectedByPhysicalPath,
          physicalRoot,
          root,
          AgentRootOwnershipIssueReason.outsideUserHome,
          repairable: false,
        );
        continue;
      }

      if (rootMetadata.type == AgentRootEntryType.symbolicLink) {
        AgentRootEntryMetadata? targetMetadata;
        try {
          targetMetadata = await _inspection.inspect(physicalRoot);
        } on Object {
          _mergeIssue(
            inspectedByPhysicalPath,
            root.path,
            root,
            AgentRootOwnershipIssueReason.inspectionFailed,
            repairable: false,
          );
          continue;
        }
        if (targetMetadata == null) {
          _mergeIssue(
            inspectedByPhysicalPath,
            root.path,
            root,
            AgentRootOwnershipIssueReason.inspectionFailed,
            repairable: false,
          );
          continue;
        }
        if (targetMetadata.type != AgentRootEntryType.directory) {
          _mergeIssue(
            inspectedByPhysicalPath,
            physicalRoot,
            root,
            AgentRootOwnershipIssueReason.notDirectory,
            repairable: false,
          );
          continue;
        }
        rootMetadata = targetMetadata;
      }

      var ownerMismatch = rootMetadata.ownerUserId != currentUserId;
      var inspectionFailed = false;
      if (!ownerMismatch) {
        try {
          await for (final descendant in _inspection.descendants(
            physicalRoot,
          )) {
            final metadata = await _inspection.inspect(descendant);
            if (metadata == null ||
                metadata.type == AgentRootEntryType.symbolicLink) {
              continue;
            }
            if (metadata.ownerUserId != currentUserId) {
              ownerMismatch = true;
              break;
            }
          }
        } on Object {
          inspectionFailed = true;
        }
      }

      if (ownerMismatch) {
        _mergeIssue(
          inspectedByPhysicalPath,
          physicalRoot,
          root,
          AgentRootOwnershipIssueReason.ownerMismatch,
          repairable: true,
        );
      } else if (inspectionFailed) {
        _mergeIssue(
          inspectedByPhysicalPath,
          physicalRoot,
          root,
          AgentRootOwnershipIssueReason.inspectionFailed,
          repairable: false,
        );
      } else {
        inspectedByPhysicalPath
            .putIfAbsent(
              physicalRoot,
              () => _InspectedRoot.clean(physicalRoot, root),
            )
            .merge(root);
      }
    }

    final inspected = inspectedByPhysicalPath.values.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    return AgentRootOwnershipAudit(
      supported: true,
      currentUserId: currentUserId,
      examinedRootCount: inspected.length,
      issues: <AgentRootOwnershipIssue>[
        for (final root in inspected)
          if (root.reason case final reason?)
            AgentRootOwnershipIssue(
              rootPath: root.path,
              agentIds: root.agentIds,
              customAgentIds: root.customAgentIds,
              roles: root.roles,
              reason: reason,
              repairable: root.repairable,
            ),
      ],
    );
  }

  Map<String, _ConfiguredRoot> _configuredRoots() {
    final roots = <String, _ConfiguredRoot>{};
    final catalog = _catalogs.current;
    for (final definition in catalog.definitions) {
      final platform = definition.onPlatform(catalog.platform);
      if (platform == null) continue;
      if (platform.globalSkillsPath case final canonical?) {
        _addConfiguredRoot(
          roots,
          canonical,
          definition.id,
          AgentSkillRootRole.canonicalActivation,
          isCustomAgent: !_catalogs.isBuiltIn(definition.id),
        );
      }
      for (final compatibility in platform.globalDiscoverySkillsPaths) {
        _addConfiguredRoot(
          roots,
          compatibility,
          definition.id,
          AgentSkillRootRole.compatibilityDiscovery,
          isCustomAgent: !_catalogs.isBuiltIn(definition.id),
        );
      }
    }
    return roots;
  }

  void _addConfiguredRoot(
    Map<String, _ConfiguredRoot> roots,
    String value,
    String agentId,
    AgentSkillRootRole role, {
    required bool isCustomAgent,
  }) {
    final normalized = path.normalize(path.absolute(value));
    roots.putIfAbsent(normalized, () => _ConfiguredRoot(normalized))
      ..agentIds.add(agentId)
      ..customAgentIds.addAll(isCustomAgent ? <String>{agentId} : const {})
      ..roles.add(role);
  }
}

void _mergeIssue(
  Map<String, _InspectedRoot> roots,
  String physicalPath,
  _ConfiguredRoot configured,
  AgentRootOwnershipIssueReason reason, {
  required bool repairable,
}) {
  final existing = roots.putIfAbsent(
    physicalPath,
    () => _InspectedRoot.issue(
      physicalPath,
      configured,
      reason,
      repairable: repairable,
    ),
  );
  existing.merge(configured);
  if (existing.reason == null || (!repairable && existing.repairable)) {
    existing.reason = reason;
    existing.repairable = repairable;
  }
}

final class _ConfiguredRoot {
  _ConfiguredRoot(this.path);

  final String path;
  final Set<String> agentIds = <String>{};
  final Set<String> customAgentIds = <String>{};
  final Set<AgentSkillRootRole> roles = <AgentSkillRootRole>{};
}

final class _InspectedRoot {
  _InspectedRoot.clean(this.path, _ConfiguredRoot configured)
    : reason = null,
      repairable = false {
    merge(configured);
  }

  _InspectedRoot.issue(
    this.path,
    _ConfiguredRoot configured,
    this.reason, {
    required this.repairable,
  }) {
    merge(configured);
  }

  final String path;
  final Set<String> agentIds = <String>{};
  final Set<String> customAgentIds = <String>{};
  final Set<AgentSkillRootRole> roles = <AgentSkillRootRole>{};
  AgentRootOwnershipIssueReason? reason;
  bool repairable;

  void merge(_ConfiguredRoot configured) {
    agentIds.addAll(configured.agentIds);
    customAgentIds.addAll(configured.customAgentIds);
    roles.addAll(configured.roles);
  }
}
