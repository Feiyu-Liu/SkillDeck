import '../../skilldeck_protocol.dart';

enum CliExitCode {
  success(0),
  failed(1),
  usage(2),
  partialBatch(3),
  appUnavailable(4),
  actionRequired(5),
  cancelled(130);

  const CliExitCode(this.value);
  final int value;
}

int commandExitCode(CommandResult result) {
  if (result.ok) return CliExitCode.success.value;
  return switch (result.error?.code) {
    'usage' ||
    'unknownAgent' ||
    'ambiguousSource' ||
    'replacementCandidateAmbiguous' => CliExitCode.usage.value,
    'partialBatch' => CliExitCode.partialBatch.value,
    'approvalPending' ||
    'approvalAlreadyPending' ||
    'actionRequired' ||
    'activationTargetOccupied' ||
    'agentRootOwnershipRepairRequired' => CliExitCode.actionRequired.value,
    'operationCancelled' || 'cancelled' => CliExitCode.cancelled.value,
    _ => CliExitCode.failed.value,
  };
}
