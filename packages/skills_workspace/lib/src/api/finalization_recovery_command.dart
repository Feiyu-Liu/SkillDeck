/// Internal dispatcher command for [SkillsRepository.resumeFinalizationRecovery].
///
/// The public facade intentionally accepts no caller-controlled recovery
/// references, paths, or operation IDs. Recovery direction remains wholly
/// defined by the durable Journal.
final class ResumeFinalizationRecoveryCommand {
  const ResumeFinalizationRecoveryCommand();
}
