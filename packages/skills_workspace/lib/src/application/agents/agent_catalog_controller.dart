import '../../domain/public_models.dart';
import '../activation/activation_result.dart';
import '../ports/agent_activation_ports.dart';
import 'agent_catalog.dart';

final class AgentCatalogReconfiguration {
  const AgentCatalogReconfiguration({
    required this.catalog,
    required this.changed,
  });

  final AgentCatalog catalog;
  final bool changed;
}

/// Owns the replaceable in-memory Agent Catalog used by source-agnostic
/// activation and discovery services.
///
/// App preferences remain responsible for persisting custom definitions. The
/// Workspace backend validates and applies one complete replacement so no
/// request observes a partially updated catalog.
final class AgentCatalogController {
  AgentCatalogController._({
    required DesktopPlatform platform,
    required AgentDetectionPort detectionPort,
    required List<AgentDefinition> builtIns,
    required AgentCatalog current,
    required List<AgentDefinition> additional,
  }) : _platform = platform,
       _detectionPort = detectionPort,
       _builtIns = List.unmodifiable(builtIns),
       _current = current,
       _additional = List.unmodifiable(additional);

  static ActivationResult<AgentCatalogController> create({
    required DesktopPlatform platform,
    required AgentDetectionPort detectionPort,
    required List<AgentDefinition> builtIns,
    List<AgentDefinition> additional = const <AgentDefinition>[],
  }) {
    final created = AgentCatalog.create(
      platform: platform,
      detectionPort: detectionPort,
      builtIns: builtIns,
      additional: additional,
    );
    final catalog = created.valueOrNull;
    if (catalog == null) {
      return copyActivationFailure<AgentCatalogController>(
        created.failureOrNull!,
      );
    }
    return ActivationSuccess<AgentCatalogController>(
      value: AgentCatalogController._(
        platform: platform,
        detectionPort: detectionPort,
        builtIns: builtIns,
        current: catalog,
        additional: additional,
      ),
    );
  }

  final DesktopPlatform _platform;
  final AgentDetectionPort _detectionPort;
  final List<AgentDefinition> _builtIns;
  AgentCatalog _current;
  List<AgentDefinition> _additional;

  AgentCatalog get current => _current;

  bool isBuiltIn(String agentId) =>
      _builtIns.any((definition) => definition.id == agentId);

  ActivationResult<AgentCatalogReconfiguration> reconfigure(
    List<AgentDefinition> additional,
  ) {
    final created = AgentCatalog.create(
      platform: _platform,
      detectionPort: _detectionPort,
      builtIns: _builtIns,
      additional: additional,
    );
    final catalog = created.valueOrNull;
    if (catalog == null) {
      return copyActivationFailure<AgentCatalogReconfiguration>(
        created.failureOrNull!,
      );
    }
    final changed = !_sameDefinitions(_additional, additional);
    if (changed) {
      _additional = List.unmodifiable(additional);
      _current = catalog;
    }
    return ActivationSuccess<AgentCatalogReconfiguration>(
      value: AgentCatalogReconfiguration(catalog: _current, changed: changed),
    );
  }
}

bool _sameDefinitions(List<AgentDefinition> left, List<AgentDefinition> right) {
  if (left.length != right.length) return false;
  final leftById = <String, AgentDefinition>{
    for (final definition in left) definition.id: definition,
  };
  final rightById = <String, AgentDefinition>{
    for (final definition in right) definition.id: definition,
  };
  if (leftById.length != left.length || rightById.length != right.length) {
    return false;
  }
  for (final entry in leftById.entries) {
    if (rightById[entry.key] != entry.value) return false;
  }
  return true;
}
