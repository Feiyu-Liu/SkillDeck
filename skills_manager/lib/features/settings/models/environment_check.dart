/// One thing the Environment check section can verify.
///
/// Adding a second check is one value here plus one reason-to-text branch in
/// the section widget; the surrounding list structure does not change.
enum EnvironmentCheckId { git }

/// Presentation tier shared by every check item.
///
/// [notChecked] and [checking] exist only here: Skill Workspace reports facts
/// about the host and has no vocabulary for "we have not asked yet".
enum EnvironmentCheckStatus { notChecked, checking, ok, attention, failed }

/// A single row of the Environment check section.
final class EnvironmentCheckItem {
  const EnvironmentCheckItem({
    required this.id,
    required this.status,
    this.reasonKey,
  });

  final EnvironmentCheckId id;
  final EnvironmentCheckStatus status;

  /// Item-specific detail resolved to a localized string at the widget layer,
  /// following the same string-code convention the rest of settings uses.
  final String? reasonKey;

  EnvironmentCheckItem copyWith({
    EnvironmentCheckStatus? status,
    Object? reasonKey = _unset,
  }) => EnvironmentCheckItem(
    id: id,
    status: status ?? this.status,
    reasonKey: reasonKey == _unset ? this.reasonKey : reasonKey as String?,
  );
}

const _unset = Object();
