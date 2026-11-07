import 'generated/skills_workspace_bindings_generated.dart' as bindings;

const int nativePingExpectedValue = 0x5357;

/// Verifies that the package-owned Native Asset can be loaded and invoked.
///
/// This is an internal scaffolding probe, not part of the public package API.
int nativePing() => bindings.skills_workspace_native_ping();
