/// CLI-local discovery contract. Extend this catalog as commands are added.
const commonFlags = <String, Object?>{
  'json': {'type': 'bool', 'description': 'Print one stable JSON document.'},
  'no-launch': {'type': 'bool', 'description': 'Do not launch the App.'},
  'wait': {
    'type': 'seconds',
    'default': 30,
    'description':
        'Requested lock wait budget; writes currently use the App default.',
  },
  'help': {'type': 'bool', 'description': 'Show CLI-local help.'},
};
const selectorFlags = <String, Object?>{
  'tag': {
    'type': 'string',
    'repeatable': true,
    'description': 'Require every named Personal Tag, case-insensitively.',
  },
  'untagged': {
    'type': 'bool',
    'description': 'Select Skills without Personal Tags.',
  },
  'favorite': {'type': 'bool', 'description': 'Select Favorites.'},
  'source': {
    'type': 'string',
    'description': 'Match a Source display locator prefix.',
  },
  'active-for': {
    'type': 'agentId',
    'description': 'Select Skills activated for this Agent.',
  },
  'project': {
    'type': 'path',
    'description': 'Match Activations at this Project Root; relative to cwd.',
  },
  'has-update': {
    'type': 'bool',
    'description': 'Select Skills with an observed available update.',
  },
  'all': {
    'type': 'bool',
    'description': 'Start from all Skills, then apply filters.',
  },
};
const writeFlags = <String, Object?>{
  'dry-run': {
    'type': 'bool',
    'description': 'Predict wouldSucceed/unchanged without mutations; runtime failures such as occupied targets may be missed.',
  },
  'keep-going': {
    'type': 'bool',
    'description': 'Continue after an item fails.',
  },
};
const approvalTimeoutFlag = <String, Object?>{
  'approval-timeout': {
    'type': 'seconds',
    'default': 90,
    'minimum': 0,
    'maximum': 600,
    'description': 'Wait up to 0–600 seconds for approval in SkillDeck; timing out leaves the request pending.',
  },
};
const destructiveFlags = <String, Object?>{
  'dry-run': {
    'type': 'bool',
    'description': 'Return destructive disclosure facts without creating an approval or changing anything.',
  },
  ...approvalTimeoutFlag,
};
const selectionArguments = <Object?>[
  {
    'name': 'refs',
    'type': 'skillIdOrSlotKey',
    'repeatable': true,
    'required': false,
  },
];
final tagSelectionFlags = <String, Object?>{
  'untagged': selectorFlags['untagged'],
  'favorite': selectorFlags['favorite'],
  'source': selectorFlags['source'],
  'active-for': selectorFlags['active-for'],
  'project': selectorFlags['project'],
  'has-update': selectorFlags['has-update'],
  'all': selectorFlags['all'],
};

final commandCatalog = <String, Map<String, Object?>>{
  'status': {
    'description': 'Show the running App, Workspace, and Project Roots.',
    'arguments': <Object?>[],
    'flags': commonFlags,
  },
  'agents': {
    'description': 'List device Agents and their global roots.',
    'arguments': <Object?>[],
    'flags': commonFlags,
  },
  'list': {
    'description': 'List selected Skills. Provide refs, filters, or --all.',
    'arguments': [
      {
        'name': 'refs',
        'type': 'skillIdOrSlotKey',
        'repeatable': true,
        'required': false,
      },
    ],
    'flags': {...commonFlags, ...selectorFlags},
  },
  'show': {
    'description': 'Show exactly one selected Skill and its documents.',
    'arguments': [
      {
        'name': 'refs',
        'type': 'skillIdOrSlotKey',
        'repeatable': true,
        'required': false,
      },
    ],
    'flags': {
      ...commonFlags,
      ...selectorFlags,
      'document': {
        'type': 'path',
        'description': 'Read a listed document (at most 512 KiB).',
      },
    },
  },
  'install': {
    'description': 'Inspect and install a Source. Without --agent, add to the library only.',
    'arguments': [
      {'name': 'source', 'type': 'sourceLocator', 'required': true},
    ],
    'flags': {
      ...commonFlags,
      ...writeFlags,
      'skill': {
        'type': 'string',
        'repeatable': true,
        'description': 'Declared name or Slot Key, case-insensitive; exclusive with --all-skills.',
      },
      'all-skills': {
        'type': 'bool',
        'description': 'Install every candidate; otherwise select the only candidate or use --skill.',
      },
      'agent': {
        'type': 'agentId',
        'repeatable': true,
        'description': 'Activate for these device Agents.',
      },
      'project': {
        'type': 'path',
        'description': 'Destination Project Root, relative to cwd; requires --agent. Registers an unknown root automatically.',
      },
    },
  },
  'source': {
    'description': 'Manage Skill Sources.',
    'arguments': <Object?>[],
    'flags': commonFlags,
    'subcommands': {
      'relink': {
        'description': 'Reconnect adopted Skills using the skills.sh lock after approval in SkillDeck. Inspects each Source; defaults to all adopted Skills.',
        'arguments': selectionArguments,
        'flags': {
          ...commonFlags,
          ...selectorFlags,
          ...destructiveFlags,
          'from-skills-lock': {
            'type': 'bool',
            'required': true,
            'description': 'Read Source hints from the skills.sh v3 lock.',
          },
          'keep-going': {
            'type': 'bool',
            'default': true,
            'description': 'Continue after an item fails (default on); --no-keep-going stops early.',
          },
        },
      },
      'replace': {
        'description': 'Replace selected Skills from one inspected Source after approval in SkillDeck. Batch candidates match by Slot Key.',
        'arguments': selectionArguments,
        'flags': {
          ...commonFlags,
          ...selectorFlags,
          ...destructiveFlags,
          'keep-going': writeFlags['keep-going'],
          'to': {
            'type': 'sourceLocator',
            'required': true,
            'description':
                'New Source; relative local paths resolve against cwd.',
          },
          'ref': {
            'type': 'string',
            'description': 'New Source ref; omitted means its default branch.',
          },
          'skill': {
            'type': 'string',
            'description': 'Candidate declared name or Slot Key; requires exactly one selected Skill.',
          },
        },
      },
    },
  },
  'remove': {
    'description': 'Request removal of selected Skills. The user must approve in SkillDeck at the reviewed Repository Revision.',
    'arguments': selectionArguments,
    'flags': {...commonFlags, ...selectorFlags, ...destructiveFlags},
  },
  'approvals': {
    'description':
        'Inspect, resume, or withdraw an App-session approval request.',
    'arguments': <Object?>[],
    'flags': commonFlags,
    'subcommands': {
      for (final action in ['wait', 'status', 'cancel'])
        action: {
          'description': switch (action) {
            'wait' =>
              'Resume waiting without withdrawing on timeout or disconnect.',
            'status' =>
              'Return pending, executing, or the original terminal result.',
            _ => 'Withdraw a pending approval; terminal outcomes remain unchanged.',
          },
          'arguments': [
            {'name': 'id', 'type': 'approvalId', 'required': true},
          ],
          'flags': {
            ...commonFlags,
            if (action == 'wait') ...approvalTimeoutFlag,
          },
        },
    },
  },
  'update': {
    'description': 'Update selected Skills with an observed available update. Never checks implicitly; run --check first. Dirty Drafts and conflicts require action in the App.',
    'arguments': selectionArguments,
    'flags': {
      ...commonFlags,
      ...selectorFlags,
      ...writeFlags,
      'check': {
        'type': 'bool',
        'description': 'Check through the App update coordinator without updating. With --dry-run, inspect current state only.',
      },
    },
  },
  for (final command in ['activate', 'deactivate'])
    command: {
      'description': 'Change selected Skills at Agent roots. An unregistered activation project is registered automatically; deactivation never registers an unused root.',
      'arguments': selectionArguments,
      'flags': {
        ...commonFlags,
        ...selectorFlags,
        ...writeFlags,
        'agent': {
          'type': 'agentId',
          'repeatable': true,
          'description': 'Device Agent member to change (required).',
        },
        'project': {
          'type': 'path',
          'description': 'Destination Project Root, relative to cwd; omitted means global.',
        },
      },
    },
  'favorite': {
    'description': 'Set Favorites for selected Skills.',
    'arguments': selectionArguments,
    'flags': {
      ...commonFlags,
      ...selectorFlags,
      ...writeFlags,
      'off': {'type': 'bool', 'description': 'Clear Favorite.'},
    },
  },
  'note': {
    'description': 'Set or clear the Note of exactly one Skill.',
    'arguments': selectionArguments,
    'flags': {
      ...commonFlags,
      ...selectorFlags,
      ...writeFlags,
      'set': {'type': 'string', 'description': 'Save a nonblank Note.'},
      'clear': {'type': 'bool', 'description': 'Delete the Note.'},
    },
  },
  'tag': {
    'description': 'Add, remove, or rename Personal Tags.',
    'arguments': <Object?>[],
    'flags': commonFlags,
    'subcommands': {
      for (final action in ['add', 'remove'])
        action: {
          'description': action == 'add'
              ? 'Assign Tags, creating missing Tags.'
              : 'Unassign existing Tags.',
          'arguments': selectionArguments,
          'flags': {
            ...commonFlags,
            ...tagSelectionFlags,
            ...writeFlags,
            'tag': {
              'type': 'string',
              'repeatable': true,
              'description': 'Tag to change (required); use other flags to filter selection.',
            },
          },
        },
      'delete': {
        'description': 'Delete a Personal Tag after approval in SkillDeck. Dry run returns the tag and assigned Skill count.',
        'arguments': [
          {'name': 'name', 'type': 'string', 'required': true},
        ],
        'flags': {...commonFlags, ...destructiveFlags},
      },
      'rename': {
        'description': 'Rename one Personal Tag.',
        'arguments': [
          {'name': 'old', 'type': 'string', 'required': true},
          {'name': 'new', 'type': 'string', 'required': true},
        ],
        'flags': {...commonFlags, ...writeFlags},
      },
    },
  },
  'help': {
    'description': 'Show this CLI-local catalog without contacting the App.',
    'arguments': [
      {'name': 'command', 'type': 'commandName', 'required': false},
    ],
    'flags': commonFlags,
  },
};

const exitCodeCatalog = <String, String>{
  '0': 'Every item succeeded or committed.',
  '1': 'Failed, including approvalDenied, approvalExpired, approvalCancelled, and approvalNotFound.',
  '2': 'Usage error.',
  '3': 'Partial batch.',
  '4': 'App unavailable (appUnavailable, appNotInstalled, appLaunchTimeout, missingHome) or protocolMismatch.',
  '5': 'User action required in the App (approvalPending, approvalAlreadyPending, actionRequired).',
  '130': 'Cancelled.',
};

// Commands forward only stable App codes, never raw diagnostics.
const knownErrorCodes = <String>[
  'usage',
  'ambiguousSource',
  'candidateNotFound',
  'replacementCandidateNotFound',
  'replacementCandidateAmbiguous',
  'replacementSlotOccupied',
  'lockUnavailable',
  'lockEntryMissing',
  'lockSourceUnsupported',
  'notAdopted',
  'alreadyInstalled',
  'checkFailed',
  'unknownAgent',
  'partialBatch',
  'actionRequired',
  'approvalPending',
  'approvalAlreadyPending',
  'approvalDenied',
  'approvalExpired',
  'approvalCancelled',
  'approvalNotFound',
  'activationTargetOccupied',
  'agentRootOwnershipRepairRequired',
  'tagNotFound',
  'tagNameConflict',
  'invalidTagName',
  'invalidNote',
  'unknownCommand',
  'skillNotFound',
  'ambiguousSelection',
  'documentNotFound',
  'documentTooLarge',
  'responseTooLarge',
  'workspaceUnavailable',
  'staleSnapshot',
  'repositoryBusy',
  'repositoryNotOpen',
  'revisionStoreCorrupt',
  'controlPlaneCorrupt',
  'stateCorrupt',
  'invalidEffectiveFilePath',
  'ioFailure',
  'operationFailed',
  'appUnavailable',
  'appNotInstalled',
  'appLaunchTimeout',
  'protocolMismatch',
  'unauthorized',
  'insecureDiscovery',
  'protocolViolation',
  'timeout',
  'missingHome',
  'internalError',
  'sourceUnavailable',
  'sourceAuthenticationRequired',
  'gitUnavailable',
  'gitFailed',
  'developerToolsRequired',
  'transportRejected',
  'httpFailure',
  'digestMismatch',
  'archiveInvalid',
  'staleInstallTakeover',
  'staleActivationTakeover',
  'invalidSkill',
  'unsupportedSkillName',
  'skillContentLimitExceeded',
  'duplicateSkillSlot',
  'sourceReplacementRequired',
  'updateUnsupported',
  'externalConflict',
  'activationUnavailable',
  'activationUnsupported',
  'projectRootNotFound',
  'invalidProjectRoot',
  'projectRootConflict',
  'agentNotFound',
  'duplicateAgentId',
  'agentRootOwnership',
  'personalTagNotFound',
  'duplicatePersonalTag',
  'operationCancelled',
  'unsupportedStateVersion',
  'unsupportedJournalVersion',
  'journalCorrupt',
  'journalMaintenanceFailed',
  'migrationFailed',
  'finalizationRecoveryFailed',
  'dirtyDraftResolutionRequired',
  'updateCandidateResolutionRequired',
  'draftChangedDuringPublish',
  'declaredNameChangeNotAllowed',
  'historicalNameMismatch',
  'rollbackFailed',
  'recoveryFailed',
  'invalidSource',
  'staleDriftReview',
  'driftResolutionUnavailable',
];

Map<String, Object?> helpCatalog([String? command]) {
  if (command != null && !commandCatalog.containsKey(command)) {
    throw const FormatException();
  }
  return {
    'commands': command == null
        ? commandCatalog
        : {command: commandCatalog[command]},
    'globalFlags': {
      ...commonFlags,
      'version': {'type': 'bool', 'description': 'Show the CLI version.'},
    },
    'selection': 'Resolve refs by id before Slot Key; refs union --all, then intersect all filters. Filters alone start from all Skills.',
    'outcomes': [
      'succeeded',
      'unchanged',
      'committedFinalizationPending',
      'failed',
      'notAttempted',
      'skipped',
      'cancelled',
      'wouldSucceed',
      'alreadyInstalled',
      'updateAvailable',
      'upToDate',
      'checkFailed',
    ],
    'exitCodes': exitCodeCatalog,
    'errorCodes': knownErrorCodes,
  };
}

String helpText([String? command]) {
  final catalog = helpCatalog(command)['commands'] as Map;
  List<String> describe(String name, Map spec) => [
    '$name: ${spec['description']}',
    for (final argument in (spec['arguments'] as List).cast<Map>())
      '  [${argument['name']}${argument['repeatable'] == true ? '...' : ''}]: ${argument['type']}',
    for (final flag in (spec['flags'] as Map).entries)
      '  --${flag.key}: ${(flag.value as Map)['description']}',
    for (final entry in (spec['subcommands'] as Map? ?? {}).entries)
      ...describe('$name ${entry.key}', entry.value as Map),
  ];
  return [
    'Usage: skilldeck <command> [refs] [options]',
    for (final entry in catalog.entries)
      ...describe('${entry.key}', entry.value as Map),
  ].join('\n');
}
