/// Stable discriminator for supported Skill source provenance.
enum SourceType { local, git, wellKnown, adoptedSnapshot }

/// Credential-free provenance needed to reacquire or explain a Skill source.
sealed class SourceDescriptor {
  const SourceDescriptor();

  /// The stable source discriminator.
  SourceType get type;

  /// Whether this source can be inspected for upstream content changes.
  bool get canCheckForUpdates => type != SourceType.adoptedSnapshot;

  /// Whether [other] denotes the same source selection.
  bool hasSameIdentity(SourceDescriptor other);
}

/// A Skill selected from an ordinary local directory.
final class LocalSourceDescriptor extends SourceDescriptor {
  /// Creates local source provenance.
  LocalSourceDescriptor({required this.locator, this.skillPath = ''}) {
    _requireNormalizedAbsolutePath(locator, 'locator');
  }

  /// The normalized absolute source directory.
  final String locator;

  /// The relative Skill path when the source exposes more than one Skill.
  final String skillPath;

  @override
  SourceType get type => SourceType.local;

  @override
  bool hasSameIdentity(SourceDescriptor other) =>
      other is LocalSourceDescriptor &&
      locator == other.locator &&
      skillPath == other.skillPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalSourceDescriptor && hasSameIdentity(other);

  @override
  int get hashCode => Object.hash(type, locator, skillPath);

  @override
  String toString() =>
      'LocalSourceDescriptor(locator: $locator, skillPath: $skillPath)';
}

/// A Skill selected from a remote or local Git repository.
final class GitSourceDescriptor extends SourceDescriptor {
  /// Creates Git source provenance without authentication material.
  GitSourceDescriptor({
    required this.locator,
    this.ref,
    this.repositorySubpath = '',
    this.skillPath = '',
  }) {
    _requireNonEmpty(locator, 'locator');
    if (ref != null) {
      _requireNonEmpty(ref!, 'ref');
    }
  }

  /// The credential-free repository locator.
  final String locator;

  /// An optional caller-selected branch, tag, or revision expression.
  final String? ref;

  /// The relative path used as the discovery root within the repository.
  final String repositorySubpath;

  /// The relative path of one selected Skill within the discovery root.
  final String skillPath;

  @override
  SourceType get type => SourceType.git;

  @override
  bool hasSameIdentity(SourceDescriptor other) =>
      other is GitSourceDescriptor &&
      locator == other.locator &&
      ref == other.ref &&
      repositorySubpath == other.repositorySubpath &&
      skillPath == other.skillPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GitSourceDescriptor && hasSameIdentity(other);

  @override
  int get hashCode =>
      Object.hash(type, locator, ref, repositorySubpath, skillPath);

  @override
  String toString() =>
      'GitSourceDescriptor(locator: $locator, ref: $ref, '
      'repositorySubpath: $repositorySubpath, skillPath: $skillPath)';
}

/// A Skill selected through a supported well-known source protocol.
final class WellKnownSourceDescriptor extends SourceDescriptor {
  /// Creates well-known source provenance.
  WellKnownSourceDescriptor({required this.locator, this.skillPath = ''}) {
    _requireNonEmpty(locator, 'locator');
  }

  /// The credential-free well-known index or archive locator.
  final String locator;

  /// The relative path of one selected Skill.
  final String skillPath;

  @override
  SourceType get type => SourceType.wellKnown;

  @override
  bool hasSameIdentity(SourceDescriptor other) =>
      other is WellKnownSourceDescriptor &&
      locator == other.locator &&
      skillPath == other.skillPath;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WellKnownSourceDescriptor && hasSameIdentity(other);

  @override
  int get hashCode => Object.hash(type, locator, skillPath);

  @override
  String toString() =>
      'WellKnownSourceDescriptor(locator: $locator, skillPath: $skillPath)';
}

/// Immutable provenance captured while adopting an unmanaged Skill snapshot.
final class AdoptedSnapshotSourceDescriptor extends SourceDescriptor {
  /// Creates adopted-snapshot provenance.
  AdoptedSnapshotSourceDescriptor({
    required this.authoritativeLocation,
    required this.contentHash,
  }) {
    _requireNormalizedAbsolutePath(
      authoritativeLocation,
      'authoritativeLocation',
    );
    _requireSha256(contentHash, 'contentHash');
  }

  /// The normalized absolute location from which the bytes were adopted.
  final String authoritativeLocation;

  /// The normalized content digest captured at adoption time.
  final String contentHash;

  @override
  SourceType get type => SourceType.adoptedSnapshot;

  @override
  bool get canCheckForUpdates => false;

  @override
  bool hasSameIdentity(SourceDescriptor other) =>
      other is AdoptedSnapshotSourceDescriptor &&
      authoritativeLocation == other.authoritativeLocation &&
      contentHash == other.contentHash;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdoptedSnapshotSourceDescriptor && hasSameIdentity(other);

  @override
  int get hashCode => Object.hash(type, authoritativeLocation, contentHash);

  @override
  String toString() =>
      'AdoptedSnapshotSourceDescriptor('
      'authoritativeLocation: $authoritativeLocation, '
      'contentHash: $contentHash)';
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requireSha256(String value, String name) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a lowercase SHA-256 digest',
    );
  }
}

void _requireNormalizedAbsolutePath(String value, String name) {
  _requireNonEmpty(value, name);
  if (!_isNormalizedPosixAbsolutePath(value) &&
      !_isNormalizedWindowsDrivePath(value) &&
      !_isNormalizedWindowsUncPath(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a fully qualified normalized absolute path',
    );
  }
}

bool _isNormalizedPosixAbsolutePath(String value) {
  if (!value.startsWith('/') || value.contains(r'\')) {
    return false;
  }
  return _hasNormalizedSegments(value, separator: '/', rootLength: 1);
}

bool _isNormalizedWindowsDrivePath(String value) {
  if (!RegExp(r'^[A-Za-z]:\\').hasMatch(value) || value.contains('/')) {
    return false;
  }
  return _hasNormalizedSegments(value, separator: r'\', rootLength: 3);
}

bool _isNormalizedWindowsUncPath(String value) {
  if (!value.startsWith(r'\\') || value.contains('/')) {
    return false;
  }
  final segments = value.substring(2).split(r'\');
  if (segments.length < 2 || segments[0].isEmpty || segments[1].isEmpty) {
    return false;
  }
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

bool _hasNormalizedSegments(
  String value, {
  required String separator,
  required int rootLength,
}) {
  if (value.length == rootLength) {
    return true;
  }
  if (value.endsWith(separator)) {
    return false;
  }
  final segments = value.substring(rootLength).split(separator);
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}
