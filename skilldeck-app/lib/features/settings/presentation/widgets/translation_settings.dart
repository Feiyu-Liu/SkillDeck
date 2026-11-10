import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/translation/data/repositories/app_translation_repository.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_manager/features/translation/presentation/view_models/skill_translation_view_model.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';
import 'package:skills_translation/skills_translation.dart';

/// Where the latest connection test stands. Null fields mean no test has run
/// since the form last changed.
final class TranslationConnectionTestState {
  const TranslationConnectionTestState.idle() : running = false, result = null;

  const TranslationConnectionTestState.running()
    : running = true,
      result = null;

  const TranslationConnectionTestState.finished(
    AppTranslationConnectionResult this.result,
  ) : running = false;

  final bool running;
  final AppTranslationConnectionResult? result;
}

class TranslationSettingsView extends StatelessWidget {
  const TranslationSettingsView({
    required this.state,
    required this.provider,
    required this.defaults,
    required this.protocol,
    required this.reasoningEnabled,
    required this.advancedExpanded,
    required this.endpointController,
    required this.modelController,
    required this.targetLanguageController,
    required this.apiKeyController,
    required this.budgetController,
    required this.concurrencyController,
    required this.maxOutputTokensController,
    required this.apiKeyFormatter,
    required this.onProviderChanged,
    required this.onProtocolChanged,
    required this.onReasoningChanged,
    required this.onToggleAdvanced,
    required this.onSave,
    required this.onRevert,
    required this.onTestConnection,
    required this.connectionTest,
    required this.dirty,
    required this.showSectionHeader,
    super.key,
  });

  final SkillTranslationState state;
  final AppTranslationProviderKind provider;
  final TranslationProviderProfile defaults;
  final AppOpenAIProtocol protocol;
  final bool reasoningEnabled;
  final bool advancedExpanded;
  final TextEditingController endpointController;
  final TextEditingController modelController;
  final TextEditingController targetLanguageController;
  final TextEditingController apiKeyController;
  final TextEditingController budgetController;
  final TextEditingController concurrencyController;
  final TextEditingController maxOutputTokensController;
  final TextInputFormatter apiKeyFormatter;
  final ValueChanged<AppTranslationProviderKind> onProviderChanged;
  final ValueChanged<AppOpenAIProtocol> onProtocolChanged;
  final ValueChanged<bool> onReasoningChanged;
  final VoidCallback onToggleAdvanced;
  final VoidCallback? onSave;
  final VoidCallback? onRevert;
  final VoidCallback? onTestConnection;
  final TranslationConnectionTestState connectionTest;
  final bool dirty;
  final bool showSectionHeader;

  @override
  Widget build(BuildContext context) {
    if (state.settingsStatus == TranslationSettingsStatus.loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    final l10n = context.l10n;
    return Column(
      key: const Key('translation-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSectionHeader) ...[
          SettingsSectionHeader(
            title: l10n.translationSettingsTitle,
            description: l10n.translationSettingsDescription,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        _TranslationStatusBanner(
          state: state,
          connectionTest: connectionTest,
          onTestConnection: onTestConnection,
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          label: l10n.translationServiceGroup,
          children: [
            SettingsRow(
              title: l10n.translationProvider,
              trailing: AppSegmentedControl<AppTranslationProviderKind>(
                key: const Key('translation-provider-control'),
                value: provider,
                segments: {
                  AppTranslationProviderKind.openAICompatible:
                      l10n.translationProviderOpenAI,
                  AppTranslationProviderKind.anthropic:
                      l10n.translationProviderAnthropic,
                },
                onChanged: onProviderChanged,
              ),
            ),
            _SettingsFieldRow(
              title: l10n.translationEndpoint,
              description: l10n.translationEndpointHint,
              field: _SettingsTextField(
                keyValue: 'translation-endpoint-field',
                controller: endpointController,
                placeholder: defaults.endpoint,
                monospace: true,
              ),
            ),
            _SettingsFieldRow(
              title: l10n.translationModel,
              field: _SettingsTextField(
                keyValue: 'translation-model-field',
                controller: modelController,
                placeholder: defaults.model,
                monospace: true,
              ),
            ),
            _SettingsFieldRow(
              title: l10n.translationApiKey,
              description: l10n.translationApiKeyHint,
              field: _SettingsTextField(
                keyValue: 'translation-api-key-field',
                controller: apiKeyController,
                obscureText: true,
                inputFormatters: [apiKeyFormatter],
                placeholder: state.profile?.hasCredential == true
                    ? l10n.translationApiKeyStored
                    : l10n.translationApiKeyOptional,
                prefixIcon: LucideIcons.lock,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          label: l10n.translationOutputGroup,
          children: [
            _SettingsFieldRow(
              title: l10n.translationTargetLanguage,
              field: _SettingsTextField(
                keyValue: 'translation-target-field',
                controller: targetLanguageController,
                placeholder: defaults.targetLanguage,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            key: const Key('translation-advanced-toggle'),
            label: advancedExpanded
                ? l10n.translationAdvancedHide
                : l10n.translationAdvancedShow,
            icon: advancedExpanded
                ? LucideIcons.chevronUp
                : LucideIcons.chevronDown,
            style: NeoButtonVariant.ghost,
            onPressed: onToggleAdvanced,
          ),
        ),
        AnimatedSize(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: advancedExpanded
              ? Padding(
                  key: const Key('translation-advanced-settings'),
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: SettingsGroup(
                    children: [
                      if (provider ==
                          AppTranslationProviderKind.openAICompatible)
                        SettingsRow(
                          title: l10n.translationProtocol,
                          trailing: AppSegmentedControl<AppOpenAIProtocol>(
                            key: const Key('translation-protocol-control'),
                            value: protocol,
                            segments: const {
                              AppOpenAIProtocol.responses: 'Responses',
                              AppOpenAIProtocol.chatCompletions:
                                  'Chat Completions',
                            },
                            onChanged: onProtocolChanged,
                          ),
                        ),
                      _SettingsFieldRow(
                        title: l10n.translationCharacterBudget,
                        field: _SettingsTextField(
                          keyValue: 'translation-budget-field',
                          controller: budgetController,
                          placeholder: defaults.segmentCharacterBudget
                              .toString(),
                        ),
                      ),
                      _SettingsFieldRow(
                        title: l10n.translationConcurrency,
                        field: _SettingsTextField(
                          keyValue: 'translation-concurrency-field',
                          controller: concurrencyController,
                          placeholder: defaults.maxConcurrentSegments
                              .toString(),
                        ),
                      ),
                      _SettingsFieldRow(
                        title: l10n.translationMaxOutputTokens,
                        field: _SettingsTextField(
                          keyValue: 'translation-max-output-field',
                          controller: maxOutputTokensController,
                          placeholder: l10n.translationOptional,
                        ),
                      ),
                      SettingsRow(
                        title: l10n.translationReasoning,
                        description: l10n.translationReasoningDescription,
                        trailing: CupertinoSwitch(
                          key: const Key('translation-reasoning-switch'),
                          value: reasoningEnabled,
                          activeTrackColor: AppPalette.of(context).success,
                          onChanged: onReasoningChanged,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (state.failureCode != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.translationSettingsError,
            key: const Key('translation-settings-error'),
            style: AppTypography.of(context).body
                .copyWith(color: AppPalette.of(context).danger),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            if (dirty)
              Text(
                l10n.translationUnsavedChanges,
                key: const Key('translation-unsaved-changes'),
                style: AppTypography.of(context).caption
                    .copyWith(color: AppPalette.of(context).warningStrong),
              ),
            AppButton(
              key: const Key('translation-settings-revert'),
              label: l10n.translationRevert,
              icon: LucideIcons.undo2,
              onPressed: dirty ? onRevert : null,
            ),
            AppButton(
              key: const Key('translation-settings-save'),
              label: l10n.translationSave,
              icon: LucideIcons.save,
              style: NeoButtonVariant.primary,
              onPressed: onSave,
            ),
          ],
        ),
      ],
    );
  }
}

class _TranslationStatusBanner extends StatelessWidget {
  const _TranslationStatusBanner({
    required this.state,
    required this.connectionTest,
    required this.onTestConnection,
  });

  final SkillTranslationState state;
  final TranslationConnectionTestState connectionTest;
  final VoidCallback? onTestConnection;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = connectionTest.result;
    final profile = state.profile;
    final configured = state.isProviderConfigured && profile != null;
    final (
      IconData icon,
      Color iconColor,
      Color background,
      String title,
      String detail,
    ) = switch ((connectionTest.running, result)) {
      (true, _) => (
        LucideIcons.loaderCircle,
        AppPalette.of(context).textSecondary,
        AppPalette.of(context).surfaceSubtle,
        l10n.translationTestRunning,
        '',
      ),
      (false, final result?) when result.succeeded => (
        LucideIcons.circleCheck,
        AppPalette.of(context).success,
        AppPalette.of(context).translationSuccessSoft,
        l10n.translationTestSucceeded,
        l10n.translationTestSucceededDetail,
      ),
      (false, final result?) => (
        LucideIcons.circleX,
        AppPalette.of(context).danger,
        AppPalette.of(context).dangerSoft,
        l10n.translationTestFailed,
        _connectionFailureText(context, result.failureCode),
      ),
      _ when configured => (
        LucideIcons.circleCheck,
        AppPalette.of(context).success,
        AppPalette.of(context).translationSuccessSoft,
        l10n.translationStatusConfigured(_providerName(context, profile)),
        _profileSummary(profile),
      ),
      _ => (
        LucideIcons.info,
        AppPalette.of(context).warningStrong,
        AppPalette.of(context).warningSoft,
        l10n.translationStatusNotConfigured,
        l10n.translationStatusNotConfiguredDetail,
      ),
    };
    return Container(
      key: const Key('translation-status-banner'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: AppCorners.smooth(color: background, radius: AppRadii.lg),
      child: Row(
        children: [
          connectionTest.running
              ? const CupertinoActivityIndicator(radius: 8)
              : Icon(icon, size: AppSizes.iconMd - 1, color: iconColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: SettingsTrailingLayout(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const Key('translation-status-title'),
                      style: AppTypography.of(context).body.copyWith(
                        color: AppPalette.of(context).textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        key: const Key('translation-status-detail'),
                        style: AppTypography.of(context).caption.copyWith(
                          color: AppPalette.of(context).bodyContent,
                        ),
                      ),
                    ],
                  ],
                ),
                AppButton(
                  key: const Key('translation-test-connection'),
                  label: l10n.translationTestConnection,
                  icon: LucideIcons.plugZap,
                  loading: connectionTest.running,
                  onPressed: connectionTest.running ? null : onTestConnection,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _providerName(
  BuildContext context,
  TranslationProviderProfile profile,
) => switch (profile.provider) {
  AppTranslationProviderKind.openAICompatible =>
    context.l10n.translationProviderOpenAIShort,
  AppTranslationProviderKind.anthropic =>
    context.l10n.translationProviderAnthropicShort,
};

String _profileSummary(TranslationProviderProfile profile) {
  final host = Uri.tryParse(profile.endpoint)?.host;
  return [
    if (host != null && host.isNotEmpty) host,
    '${profile.model} → ${profile.targetLanguage}',
  ].join(' · ');
}

String _connectionFailureText(BuildContext context, String? code) {
  final l10n = context.l10n;
  if (code == 'credential_required') {
    return l10n.translationTestFailedCredentialRequired;
  }
  if (code == 'invalid_configuration') {
    return l10n.translationTestFailedConfiguration;
  }
  if (code == 'credential_unavailable') {
    return l10n.translationTestFailedAuthentication;
  }
  final failure = TranslationFailureCode.values
      .where((value) => value.name == code)
      .firstOrNull;
  return switch (failure) {
    TranslationFailureCode.authenticationFailed ||
    TranslationFailureCode.accessDenied =>
      l10n.translationTestFailedAuthentication,
    TranslationFailureCode.rateLimited => l10n.translationTestFailedRateLimited,
    TranslationFailureCode.networkUnavailable ||
    TranslationFailureCode.providerUnavailable ||
    TranslationFailureCode.timedOut => l10n.translationTestFailedNetwork,
    TranslationFailureCode.requestRejected ||
    TranslationFailureCode.invalidResponse =>
      l10n.translationTestFailedRejected,
    TranslationFailureCode.invalidConfiguration =>
      l10n.translationTestFailedConfiguration,
    _ => l10n.translationTestFailedUnknown,
  };
}

/// A [SettingsRow] whose control is a text field. The field moves under the
/// title when the row is too narrow to hold both side by side.
class _SettingsFieldRow extends StatelessWidget {
  const _SettingsFieldRow({
    required this.title,
    required this.field,
    this.description,
  });

  final String title;
  final String? description;
  final Widget field;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 560) {
        return SettingsRow(
          title: title,
          description: description,
          trailing: SizedBox(width: 300, child: field),
        );
      }
      return SettingsRow(title: title, description: description, below: field);
    },
  );
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.keyValue,
    required this.controller,
    this.placeholder,
    this.obscureText = false,
    this.inputFormatters,
    this.monospace = false,
    this.prefixIcon,
  });

  final String keyValue;
  final TextEditingController controller;
  final String? placeholder;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;
  final bool monospace;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final style = monospace
        ? AppTypography.of(context).mono
              .copyWith(color: AppPalette.of(context).textPrimary)
        : AppTypography.of(context).body.copyWith(
            color: AppPalette.of(context).textPrimary,
            fontSize: 13,
          );
    return CupertinoTextField(
      key: Key(keyValue),
      controller: controller,
      obscureText: obscureText,
      inputFormatters: inputFormatters,
      placeholder: placeholder,
      placeholderStyle: style.copyWith(
        color: AppPalette.of(context).controlInactive,
      ),
      prefix: prefixIcon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Icon(
                prefixIcon,
                size: AppSizes.iconSm - 1,
                color: AppPalette.of(context).textMuted,
              ),
            ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.of(context).surface,
        border: Border.all(
          color: AppPalette.of(context).borderStrong,
          width: 0.8,
        ),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      style: style,
    );
  }
}
