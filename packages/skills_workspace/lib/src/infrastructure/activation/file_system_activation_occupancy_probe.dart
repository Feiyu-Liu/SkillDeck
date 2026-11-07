import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../application/activation/activation_models.dart';
import '../../application/activation/activation_result.dart';
import '../../application/ports/agent_activation_ports.dart';
import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';
import '../../domain/source_descriptor.dart';
import '../content/normalized_skill_tree.dart';
import '../source/local_source.dart';
import '../source/source_models.dart';
import '../source/source_result.dart';

typedef RepositoryCopyPathForSkill = String Function(ManagedSkill skill);

/// Classifies unmanaged activation targets using canonical Skill-tree hashes.
final class FileSystemActivationOccupancyProbe
    implements ActivationOccupancyProbePort {
  FileSystemActivationOccupancyProbe({
    required RepositoryCopyPathForSkill repositoryCopyPathForSkill,
    required ActivationLocationIdentityPort locationIdentity,
    LocalSourceAdapter? localSource,
  }) : _repositoryCopyPathForSkill = repositoryCopyPathForSkill,
       _locationIdentity = locationIdentity,
       _localSource = localSource ?? LocalSourceAdapter();

  final RepositoryCopyPathForSkill _repositoryCopyPathForSkill;
  final ActivationLocationIdentityPort _locationIdentity;
  final LocalSourceAdapter _localSource;

  @override
  Future<ActivationResult<InspectedActivationOccupancy?>> inspect({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return ActivationFailure<InspectedActivationOccupancy?>(
        code: ActivationFailureCode.operationCancelled,
      );
    }
    try {
      final type = await FileSystemEntity.type(targetPath, followLinks: false);
      switch (type) {
        case FileSystemEntityType.notFound:
          return ActivationSuccess<InspectedActivationOccupancy?>(value: null);
        case FileSystemEntityType.pipe:
        case FileSystemEntityType.unixDomainSock:
          return ActivationSuccess<InspectedActivationOccupancy?>(
            value: InspectedActivationOccupancy(
              managedSkillId: skill.id,
              slotKey: skill.slotKey,
              target: target,
              targetPath: targetPath,
              kind: InspectedActivationOccupancyKind.unsupported,
              contentRelation: InspectedActivationContentRelation.indeterminate,
              fingerprint: 'unsupported:$type',
              replaceable: false,
            ),
          );
        case FileSystemEntityType.file:
          return ActivationSuccess<InspectedActivationOccupancy?>(
            value: InspectedActivationOccupancy(
              managedSkillId: skill.id,
              slotKey: skill.slotKey,
              target: target,
              targetPath: targetPath,
              kind: InspectedActivationOccupancyKind.file,
              contentRelation: InspectedActivationContentRelation.indeterminate,
              fingerprint: 'file:${await _fingerprintFile(targetPath)}',
              replaceable: true,
            ),
          );
        case FileSystemEntityType.directory:
          return await _inspectDirectory(
            skill: skill,
            target: target,
            targetPath: targetPath,
            kind: InspectedActivationOccupancyKind.skillDirectory,
            invalidKind: InspectedActivationOccupancyKind.invalidDirectory,
            cancellationToken: cancellationToken,
          );
        case FileSystemEntityType.link:
          final rawTarget = await Link(targetPath).target();
          final followed = await FileSystemEntity.type(
            targetPath,
            followLinks: true,
          );
          if (followed != FileSystemEntityType.directory) {
            final missing = await _linkReferentIsMissing(targetPath);
            return ActivationSuccess<InspectedActivationOccupancy?>(
              value: InspectedActivationOccupancy(
                managedSkillId: skill.id,
                slotKey: skill.slotKey,
                target: target,
                targetPath: targetPath,
                kind: InspectedActivationOccupancyKind.brokenSymbolicLink,
                contentRelation:
                    InspectedActivationContentRelation.indeterminate,
                fingerprint: 'link:${sha256.convert(utf8.encode(rawTarget))}',
                replaceable: true,
                linkTarget: rawTarget,
                linkReferentMissing: missing,
                linkReferentUncertain:
                    followed == FileSystemEntityType.notFound && !missing,
              ),
            );
          }
          final resolvedTarget = path.normalize(
            await Directory(targetPath).resolveSymbolicLinks(),
          );
          final repositoryPath = await _canonicalPath(
            _repositoryCopyPathForSkill(skill),
          );
          return await _inspectDirectory(
            skill: skill,
            target: target,
            targetPath: targetPath,
            kind: InspectedActivationOccupancyKind.skillSymbolicLink,
            invalidKind: InspectedActivationOccupancyKind.brokenSymbolicLink,
            cancellationToken: cancellationToken,
            linkTarget: rawTarget,
            pointsToRepositoryCopy:
                _locationIdentity.key(resolvedTarget) ==
                _locationIdentity.key(repositoryPath),
          );
      }
      return ActivationFailure<InspectedActivationOccupancy?>(
        code: ActivationFailureCode.activationUnavailable,
        context: <String, Object?>{
          'managedSkillId': skill.id.value,
          'slotKey': skill.slotKey,
          'location': target.location,
          'targetPath': targetPath,
          'reason': 'unsupportedTargetType',
        },
      );
    } on FileSystemException {
      return ActivationFailure<InspectedActivationOccupancy?>(
        code: ActivationFailureCode.activationUnavailable,
        context: <String, Object?>{
          'managedSkillId': skill.id.value,
          'slotKey': skill.slotKey,
          'location': target.location,
          'targetPath': targetPath,
          'reason': 'targetUnreadable',
        },
      );
    }
  }

  Future<ActivationResult<InspectedActivationOccupancy?>> _inspectDirectory({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required InspectedActivationOccupancyKind kind,
    required InspectedActivationOccupancyKind invalidKind,
    required CancellationToken cancellationToken,
    String? linkTarget,
    bool pointsToRepositoryCopy = false,
  }) async {
    final acquiredResult = await _localSource.acquire(
      LocalSourceDescriptor(locator: path.normalize(path.absolute(targetPath))),
      options: const SkillDiscoveryOptions(includeInternal: true),
      cancellation: _CancellationSignal(cancellationToken),
    );
    if (cancellationToken.isCancelled ||
        acquiredResult.failureOrNull?.code == SourceFailureCode.cancelled) {
      return ActivationFailure<InspectedActivationOccupancy?>(
        code: ActivationFailureCode.operationCancelled,
      );
    }
    final exact = acquiredResult.valueOrNull?.skills
        .where((candidate) => candidate.skillPath.isEmpty)
        .firstOrNull;
    if (exact != null) {
      final relation = exact.slotKey != skill.slotKey
          ? InspectedActivationContentRelation.indeterminate
          : exact.tree.contentHash == skill.currentRevision.contentHash
          ? InspectedActivationContentRelation.matchesCurrentRevision
          : InspectedActivationContentRelation.differsFromCurrentRevision;
      final linkFrame = linkTarget == null ? '' : '$linkTarget\u0000';
      return ActivationSuccess<InspectedActivationOccupancy?>(
        value: InspectedActivationOccupancy(
          managedSkillId: skill.id,
          slotKey: skill.slotKey,
          target: target,
          targetPath: targetPath,
          kind: kind,
          contentRelation: relation,
          fingerprint:
              '${kind.name}:${sha256.convert(utf8.encode('$linkFrame${exact.slotKey}\u0000${exact.tree.contentHash}'))}',
          replaceable: true,
          existingSlotKey: exact.slotKey,
          rootSkillPresent: true,
          existingDeclaredName: exact.declaredName,
          existingContentHash: exact.tree.contentHash,
          linkTarget: linkTarget,
          pointsToRepositoryCopy: pointsToRepositoryCopy,
        ),
      );
    }

    final fingerprint = await _fingerprintTree(
      targetPath,
      cancellationToken: cancellationToken,
    );
    if (cancellationToken.isCancelled) {
      return ActivationFailure<InspectedActivationOccupancy?>(
        code: ActivationFailureCode.operationCancelled,
      );
    }
    if (fingerprint == null) {
      return ActivationFailure<InspectedActivationOccupancy?>(
        code: ActivationFailureCode.activationUnavailable,
        context: <String, Object?>{
          'managedSkillId': skill.id.value,
          'slotKey': skill.slotKey,
          'location': target.location,
          'targetPath': targetPath,
          'reason': 'targetNotSafelyReplaceable',
        },
      );
    }
    final linkFrame = linkTarget == null ? '' : '$linkTarget\u0000';
    return ActivationSuccess<InspectedActivationOccupancy?>(
      value: InspectedActivationOccupancy(
        managedSkillId: skill.id,
        slotKey: skill.slotKey,
        target: target,
        targetPath: targetPath,
        occupantFailureCode: acquiredResult.failureOrNull?.code.name,
        occupantFailureReason:
            acquiredResult.failureOrNull?.context['reason'] is String
            ? acquiredResult.failureOrNull!.context['reason']! as String
            : acquiredResult.failureOrNull == null
            ? 'noRootSkill'
            : null,
        directoryIsEmpty: await Directory(
          targetPath,
        ).list(followLinks: false).isEmpty,
        rootSkillPresent:
            await FileSystemEntity.type(
              path.join(targetPath, 'SKILL.md'),
              followLinks: false,
            ) !=
            FileSystemEntityType.notFound,
        kind: invalidKind,
        contentRelation: InspectedActivationContentRelation.indeterminate,
        fingerprint:
            '${invalidKind.name}:${sha256.convert(utf8.encode('$linkFrame$fingerprint'))}',
        replaceable: true,
        linkTarget: linkTarget,
        pointsToRepositoryCopy: pointsToRepositoryCopy,
      ),
    );
  }
}

final class _CancellationSignal implements SourceCancellationSignal {
  const _CancellationSignal(this._token);

  final CancellationToken _token;

  @override
  bool get isCancelled => _token.isCancelled;

  @override
  Future<void> get whenCancelled => _token.whenCancelled;
}

Future<String> _canonicalPath(String targetPath) async {
  try {
    return path.normalize(await Directory(targetPath).resolveSymbolicLinks());
  } on FileSystemException {
    return path.normalize(path.absolute(targetPath));
  }
}

Future<String> _fingerprintFile(String targetPath) async {
  final digest = await sha256.bind(File(targetPath).openRead()).first;
  return digest.toString();
}

Future<String?> _fingerprintTree(
  String root, {
  required CancellationToken cancellationToken,
}) async {
  var fileCount = 0;
  var byteSize = 0;

  Future<String?> fingerprint(String targetPath) async {
    if (cancellationToken.isCancelled) {
      return null;
    }
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        fileCount += 1;
        final stat = await File(targetPath).stat();
        byteSize += stat.size;
        if (fileCount > maximumNormalizedSkillFileCount ||
            byteSize > maximumNormalizedSkillByteSize) {
          return null;
        }
        return 'f:${await _fingerprintFile(targetPath)}';
      case FileSystemEntityType.link:
        return 'l:${await Link(targetPath).target()}';
      case FileSystemEntityType.directory:
        final entries =
            await Directory(targetPath).list(followLinks: false).toList()
              ..sort(
                (left, right) => path
                    .basename(left.path)
                    .compareTo(path.basename(right.path)),
              );
        final frames = <String>[];
        for (final entry in entries) {
          final child = await fingerprint(entry.path);
          if (child == null) {
            return null;
          }
          frames.add('${path.basename(entry.path)}\u0000$child');
        }
        return 'd:${sha256.convert(utf8.encode(frames.join('\u0001')))}';
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        return null;
    }
    return null;
  }

  try {
    return await fingerprint(root);
  } on FileSystemException {
    return null;
  }
}

/// Only an explicit missing-path error proves a dangling referent. Type/exists
/// APIs fold permission errors and cycles into notFound and are insufficient.
Future<bool> _linkReferentIsMissing(String linkPath) async {
  try {
    await Link(linkPath).resolveSymbolicLinks();
    return false;
  } on FileSystemException catch (error) {
    final code = error.osError?.errorCode;
    return code == 2 || (Platform.isWindows && code == 3);
  }
}
