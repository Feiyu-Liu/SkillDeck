/// Whether the host can run system Git, and if not, why.
///
/// Every value is a successful classification rather than a failure: the probe
/// that produces one always completes. "Not yet checked" is deliberately
/// absent — the App owns that state, so no caller can mistake an unprobed
/// default for an answer.
enum GitEnvironmentStatus {
  /// System Git ran and reported a version.
  available,

  /// No Git executable could be started at all.
  notInstalled,

  /// The host's developer command line tools are missing. On macOS the probe
  /// itself asks the operating system to present its install dialog.
  developerToolsRequired,

  /// A developer command line tools install is already under way.
  developerToolsInstalling,

  /// The probe ran but its outcome was not recognizable.
  probeFailed,
}

/// The result of one host Git capability probe.
///
/// Carries no version string and no diagnostic: raw process output must never
/// reach a caller, and the App presents status rather than build details.
final class GitEnvironmentReport {
  const GitEnvironmentReport({required this.status});

  final GitEnvironmentStatus status;
}
