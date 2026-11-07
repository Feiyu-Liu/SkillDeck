import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/activation/activation_result.dart';
import '../../application/ports/agent_activation_ports.dart';
import '../../domain/public_models.dart';

final class FileSystemActivationUpdateValidator
    implements ActivationUpdateValidationPort {
  FileSystemActivationUpdateValidator({
    required ActivationLocationIdentityPort locationIdentity,
  }) : _locationIdentity = locationIdentity;

  final ActivationLocationIdentityPort _locationIdentity;
  int _probeCounter = 0;

  @override
  Future<ActivationResult<void>> validateCopyTarget({
    required SkillActivation activation,
    required String targetPath,
  }) async {
    final unavailable = await _validateLocation(activation.location);
    if (unavailable != null) {
      return unavailable;
    }
    _probeCounter += 1;
    final probe = File(
      path.join(
        activation.location,
        '.skills-workspace-write-probe-$pid-$_probeCounter',
      ),
    );
    RandomAccessFile? opened;
    try {
      opened = await probe.open(mode: FileMode.write);
      await opened.flush();
      await opened.close();
      opened = null;
      await probe.delete();
      return ActivationSuccess<void>(value: null);
    } on FileSystemException {
      return ActivationFailure<void>(
        code: ActivationFailureCode.activationUnavailable,
        context: <String, Object?>{
          'location': activation.location,
          'targetPath': targetPath,
          'reason': 'locationNotWritable',
        },
      );
    } finally {
      try {
        await opened?.close();
        if (await probe.exists()) {
          await probe.delete();
        }
      } on FileSystemException {
        // The validation result remains authoritative.
      }
    }
  }

  @override
  Future<ActivationResult<void>> validateSymbolicLink({
    required SkillActivation activation,
    required String targetPath,
    required String expectedLinkTarget,
  }) async {
    final unavailable = await _validateLocation(activation.location);
    if (unavailable != null) {
      return unavailable;
    }
    try {
      final type = await FileSystemEntity.type(targetPath, followLinks: false);
      if (type != FileSystemEntityType.link) {
        return _failure(activation, targetPath, reason: 'symbolicLinkMissing');
      }
      final storedTarget = await Link(targetPath).target();
      final absoluteTarget = path.isAbsolute(storedTarget)
          ? storedTarget
          : path.join(path.dirname(targetPath), storedTarget);
      if (_locationIdentity.key(absoluteTarget) !=
          _locationIdentity.key(expectedLinkTarget)) {
        return _failure(
          activation,
          targetPath,
          reason: 'symbolicLinkTargetMismatch',
        );
      }
      if (await FileSystemEntity.type(expectedLinkTarget, followLinks: true) !=
          FileSystemEntityType.directory) {
        return _failure(
          activation,
          targetPath,
          reason: 'repositoryCopyUnavailable',
        );
      }
      return ActivationSuccess<void>(value: null);
    } on FileSystemException {
      return _failure(activation, targetPath, reason: 'targetUnreadable');
    }
  }

  Future<ActivationFailure<void>?> _validateLocation(String location) async {
    try {
      if (await FileSystemEntity.type(location, followLinks: true) ==
          FileSystemEntityType.directory) {
        return null;
      }
    } on FileSystemException {
      // Mapped to the same stable failure below.
    }
    return ActivationFailure<void>(
      code: ActivationFailureCode.activationUnavailable,
      context: <String, Object?>{
        'location': location,
        'reason': 'locationUnavailable',
      },
    );
  }

  ActivationFailure<void> _failure(
    SkillActivation activation,
    String targetPath, {
    required String reason,
  }) => ActivationFailure<void>(
    code: ActivationFailureCode.activationUnavailable,
    context: <String, Object?>{
      'location': activation.location,
      'targetPath': targetPath,
      'reason': reason,
    },
  );
}
