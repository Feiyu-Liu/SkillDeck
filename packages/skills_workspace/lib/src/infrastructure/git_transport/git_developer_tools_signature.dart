/// Whether a Git diagnostic reports that the host's developer command line
/// tools are missing or still installing.
enum GitDeveloperToolsSignal {
  /// The diagnostic says nothing about host developer tools.
  absent,

  /// The tools are missing; the host has been asked to install them.
  installRequired,

  /// An install is already under way, so retrying now still fails.
  installInProgress,
}

/// Classifies a redacted Git diagnostic for the macOS developer-tools shim.
///
/// macOS ships `/usr/bin/git` as a stub that starts successfully, asks the OS
/// to present its own install dialog, and then exits non-zero. Without this
/// classification the exit reads as an ordinary command failure and the user is
/// told to check their source address, which can never succeed.
///
/// Both the failure mapper and the environment probe call this so a single
/// substring table decides the answer; two tables would eventually disagree and
/// report that Git is fine while installs keep failing.
///
/// The check is deliberately not gated on the host platform. The mapper is
/// otherwise a pure function, and gating would make its tests platform
/// dependent — leaving the new classification untested on the Linux tier that
/// gates every pull request. No Linux or Windows Git emits these phrases.
GitDeveloperToolsSignal classifyGitDeveloperToolsSignal(String diagnostic) {
  final lower = diagnostic.toLowerCase();
  // An in-progress install is a subset of the xcode-select family, so it has to
  // be recognized before the broader "install required" phrases.
  if (lower.contains('install requested for command line developer tools') ||
      (lower.contains('command line developer tools') &&
          lower.contains('being installed'))) {
    return GitDeveloperToolsSignal.installInProgress;
  }
  if (lower.contains('xcode-select:') ||
      lower.contains('no developer tools were found') ||
      lower.contains('requesting install') ||
      lower.contains('command line developer tools') ||
      lower.contains('not a developer tool or in path') ||
      (lower.contains('requires xcode') &&
          lower.contains('active developer directory'))) {
    return GitDeveloperToolsSignal.installRequired;
  }
  return GitDeveloperToolsSignal.absent;
}
