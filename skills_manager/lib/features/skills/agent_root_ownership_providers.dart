import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_coordinator.dart';
import 'package:skills_manager/features/skills/data/services/agent_root_ownership_repair_service.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';

final agentRootOwnershipRepairServiceProvider =
    Provider<AgentRootOwnershipRepairService>((ref) {
      throw UnimplementedError(
        'An AgentRootOwnershipRepairService override is required.',
      );
    });

final agentRootOwnershipReviewPresenterProvider =
    Provider<AgentRootOwnershipReviewPresenter>((ref) {
      throw UnimplementedError(
        'An AgentRootOwnershipReviewPresenter override is required.',
      );
    });

final agentRootOwnershipCoordinatorProvider =
    Provider<AgentRootOwnershipCoordinator>((ref) {
      return AgentRootOwnershipCoordinator(
        repository: ref.watch(rawSkillsWorkspaceRepositoryProvider),
        repairService: ref.watch(agentRootOwnershipRepairServiceProvider),
        reviewPresenter: ref.watch(agentRootOwnershipReviewPresenterProvider),
      );
    });
