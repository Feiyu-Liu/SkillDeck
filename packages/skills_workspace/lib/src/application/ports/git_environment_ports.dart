import '../../domain/git_environment.dart';

/// Reports whether the host can run system Git.
///
/// Implementations must be lazy: constructing one starts no process, because
/// probing on an affected macOS host causes the operating system to present an
/// install dialog. Only an explicit caller may trigger that.
abstract interface class GitEnvironmentProbe {
  Future<GitEnvironmentReport> probe();
}
