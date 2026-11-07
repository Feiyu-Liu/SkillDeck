import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/settings/presentation/widgets/command_line_settings.dart';
import 'package:skills_manager/features/settings/presentation/settings_section.dart';
import 'package:skills_manager/features/settings/presentation/widgets/about_settings.dart';
import 'package:skills_manager/features/settings/presentation/widgets/agents_settings.dart';
import 'package:skills_manager/features/settings/presentation/widgets/appearance_settings.dart';
import 'package:skills_manager/features/settings/presentation/widgets/general_settings.dart';
import 'package:skills_manager/features/settings/presentation/widgets/maintenance_settings.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/settings/presentation/widgets/translation_settings.dart';
import 'package:skills_manager/features/translation/models/translation_settings.dart';
import 'package:skills_manager/features/translation/presentation/view_models/skill_translation_view_model.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/scrolling/app_scroll_controller.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_page_content.dart';
import 'package:skills_manager/shared/widgets/app_page_template.dart';
import 'package:skills_manager/shared/widgets/app_sidebar.dart';

const _storedCredentialMask = '••••••••';

/// Page width at which the section list and the selected section sit side by
/// side. Narrower windows show the list and each section as separate pages.
const _splitViewBreakpoint = 600.0;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({this.selectedSection, super.key});

  final SettingsSection? selectedSection;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final ScrollController _scrollController;
  final _endpointController = TextEditingController();
  final _modelController = TextEditingController();
  final _targetLanguageController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _budgetController = TextEditingController();
  final _concurrencyController = TextEditingController();
  final _maxOutputTokensController = TextEditingController();
  AppTranslationProviderKind _provider =
      AppTranslationProviderKind.openAICompatible;
  AppOpenAIProtocol _protocol = AppOpenAIProtocol.responses;
  bool _reasoningEnabled = false;
  bool _advancedExpanded = false;
  bool _savingProfile = false;
  String? _profileFingerprint;
  AppTranslationProviderKind? _loadedProvider;

  /// The form as it was last loaded from the saved profile, compared against
  /// the current form to tell whether it has unsaved changes.
  String? _loadedForm;
  TranslationConnectionTestState _connectionTest =
      const TranslationConnectionTestState.idle();
  int _connectionTestGeneration = 0;

  List<TextEditingController> get _formControllers => [
    _endpointController,
    _modelController,
    _targetLanguageController,
    _apiKeyController,
    _budgetController,
    _concurrencyController,
    _maxOutputTokensController,
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = AppScrollControllers.create(debugLabel: 'settings');
    for (final controller in _formControllers) {
      controller.addListener(_formChanged);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _formControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final translation = ref.watch(skillTranslationViewModelProvider);
    final profile = translation.profile;
    if (profile != null && _profileFingerprint != _fingerprint(profile)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadProfile(profile);
      });
    }
    return LayoutBuilder(
      builder: (context, pageConstraints) {
        final wide = pageConstraints.maxWidth >= _splitViewBreakpoint;
        // A wide window always shows a section; the list alone is only the
        // narrow window's landing page.
        final section =
            widget.selectedSection ??
            (wide ? SettingsSection.appearance : null);
        return AppPageTemplate(
          controller: _scrollController,
          scrollViewKey: const Key('settings-page-scroll'),
          blurKey: const Key('settings-top-blur'),
          breadcrumb: context.l10n.settingsBreadcrumb,
          breadcrumbIcon: NavSection.settings.icon,
          title: section == null || wide
              ? context.l10n.settingsTitle
              : _sectionTitle(context, section),
          commandLeading: !wide && section != null
              ? AppIconButton(
                  key: const Key('settings-detail-back'),
                  icon: LucideIcons.arrowLeft,
                  tooltip: context.l10n.commonBack,
                  size: AppSizes.pageCommandBarHeight,
                  iconSize: AppSizes.iconMd,
                  foregroundColor: AppPalette.of(context).textPrimary,
                  onPressed: () => context.go(settingsLocation(null)),
                )
              : null,
          titleKey: const Key('settings-page-title'),
          slivers: [
            AppPageSliverContent(
              sliver: SliverToBoxAdapter(
                key: const Key('settings-page-body'),
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.xxl,
                  ),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 184,
                              child: _SettingsSectionList(
                                selectedSection: section,
                                onSectionSelected: (value) =>
                                    context.go(settingsLocation(value)),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xxl),
                            Expanded(
                              child: _buildSectionDetail(
                                context,
                                section!,
                                translation,
                                profile,
                                showSectionHeader: true,
                              ),
                            ),
                          ],
                        )
                      : section == null
                      ? _SettingsSectionList(
                          selectedSection: null,
                          onSectionSelected: (value) =>
                              context.go(settingsLocation(value)),
                        )
                      : _buildSectionDetail(
                          context,
                          section,
                          translation,
                          profile,
                          showSectionHeader: false,
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionDetail(
    BuildContext context,
    SettingsSection section,
    SkillTranslationState translation,
    TranslationProviderProfile? profile, {
    required bool showSectionHeader,
  }) => switch (section) {
    SettingsSection.general => GeneralSettings(
      showSectionHeader: showSectionHeader,
    ),
    SettingsSection.appearance => AppearanceSettings(
      showSectionHeader: showSectionHeader,
    ),
    SettingsSection.agents => AgentsSettings(
      showSectionHeader: showSectionHeader,
    ),
    SettingsSection.translation => TranslationSettingsView(
      state: translation,
      provider: _provider,
      defaults: _translationDefaultsFor(_provider),
      protocol: _protocol,
      reasoningEnabled: _reasoningEnabled,
      advancedExpanded: _advancedExpanded,
      endpointController: _endpointController,
      modelController: _modelController,
      targetLanguageController: _targetLanguageController,
      apiKeyController: _apiKeyController,
      budgetController: _budgetController,
      concurrencyController: _concurrencyController,
      maxOutputTokensController: _maxOutputTokensController,
      apiKeyFormatter: _maskedKeyFormatter,
      onProviderChanged: _changeProvider,
      onProtocolChanged: (value) {
        _protocol = value;
        _formChanged();
      },
      onReasoningChanged: (value) {
        _reasoningEnabled = value;
        _formChanged();
      },
      onToggleAdvanced: () =>
          setState(() => _advancedExpanded = !_advancedExpanded),
      onSave: profile == null || _savingProfile ? null : () => _save(profile),
      onRevert: profile == null || _savingProfile
          ? null
          : () => _loadProfile(profile),
      onTestConnection: profile == null || _savingProfile
          ? null
          : () => unawaited(_testConnection(profile)),
      connectionTest: _connectionTest,
      dirty: _isFormDirty,
      showSectionHeader: showSectionHeader,
    ),
    SettingsSection.commandLine => CommandLineSettings(
      showSectionHeader: showSectionHeader,
    ),
    SettingsSection.maintenance => MaintenanceSettings(
      showSectionHeader: showSectionHeader,
    ),
    SettingsSection.about => const AboutSettings(),
  };

  String _currentForm() => [
    _provider.name,
    _protocol.name,
    _reasoningEnabled,
    for (final controller in _formControllers) controller.text,
  ].join('\u0000');

  bool get _isFormDirty => _loadedForm != null && _loadedForm != _currentForm();

  /// Any edit makes an earlier connection test result stale.
  void _formChanged() {
    if (!mounted) return;
    setState(() {
      if (!_connectionTest.running) {
        _connectionTest = const TranslationConnectionTestState.idle();
      }
    });
  }

  void _loadProfile(TranslationProviderProfile profile) {
    _profileFingerprint = _fingerprint(profile);
    _loadedProvider = profile.provider;
    _provider = profile.provider;
    _protocol = profile.protocol;
    _reasoningEnabled = profile.reasoningEnabled;
    final isDefault = _isDefaultTranslationProfile(profile);
    _endpointController.text = isDefault ? '' : profile.endpoint;
    _modelController.text = isDefault ? '' : profile.model;
    _targetLanguageController.text = isDefault ? '' : profile.targetLanguage;
    _budgetController.text = isDefault
        ? ''
        : profile.segmentCharacterBudget.toString();
    _concurrencyController.text = isDefault
        ? ''
        : profile.maxConcurrentSegments.toString();
    _maxOutputTokensController.text = profile.maxOutputTokens?.toString() ?? '';
    _apiKeyController.text = profile.hasCredential ? _storedCredentialMask : '';
    _loadedForm = _currentForm();
    _connectionTestGeneration++;
    setState(
      () => _connectionTest = const TranslationConnectionTestState.idle(),
    );
  }

  void _changeProvider(AppTranslationProviderKind provider) {
    if (_provider == provider) return;
    _provider = provider;
    _endpointController.clear();
    _modelController.clear();
    _targetLanguageController.clear();
    _budgetController.clear();
    _concurrencyController.clear();
    _maxOutputTokensController.clear();
    _apiKeyController.text =
        provider == _loadedProvider &&
            ref
                    .read(skillTranslationViewModelProvider)
                    .profile
                    ?.hasCredential ==
                true
        ? _storedCredentialMask
        : '';
    _formChanged();
  }

  /// The profile the form describes, built on [loadedProfile] so fields the
  /// form does not edit, such as the credential reference, carry over.
  TranslationProviderProfile _draftProfile(
    TranslationProviderProfile loadedProfile,
  ) {
    final defaults = _translationDefaultsFor(_provider);
    final maxOutputText = _maxOutputTokensController.text.trim();
    String orDefault(TextEditingController controller, String fallback) {
      final value = controller.text.trim();
      return value.isEmpty ? fallback : value;
    }

    return loadedProfile.copyWith(
      provider: _provider,
      endpoint: orDefault(_endpointController, defaults.endpoint),
      model: orDefault(_modelController, defaults.model),
      targetLanguage: orDefault(
        _targetLanguageController,
        defaults.targetLanguage,
      ),
      protocol: _protocol,
      segmentCharacterBudget:
          int.tryParse(_budgetController.text.trim()) ??
          defaults.segmentCharacterBudget,
      maxConcurrentSegments:
          int.tryParse(_concurrencyController.text.trim()) ??
          defaults.maxConcurrentSegments,
      maxOutputTokens: maxOutputText.isEmpty
          ? null
          : int.tryParse(maxOutputText) ?? 0,
      reasoningEnabled: _reasoningEnabled,
    );
  }

  Future<void> _testConnection(TranslationProviderProfile loadedProfile) async {
    if (_connectionTest.running) return;
    final generation = ++_connectionTestGeneration;
    final enteredKey = _apiKeyController.text.trim();
    final providerChanged =
        _loadedProvider != null && _loadedProvider != _provider;
    final usesStoredKey = enteredKey == _storedCredentialMask;
    setState(
      () => _connectionTest = const TranslationConnectionTestState.running(),
    );
    final result = await ref
        .read(skillTranslationViewModelProvider.notifier)
        .testConnection(
          _draftProfile(loadedProfile),
          replacementApiKey: usesStoredKey ? null : enteredKey,
          useStoredCredential: usesStoredKey && !providerChanged,
        );
    // A save, revert, or newer test made this result stale.
    if (!mounted || generation != _connectionTestGeneration) return;
    setState(
      () => _connectionTest = TranslationConnectionTestState.finished(result),
    );
  }

  Future<void> _save(TranslationProviderProfile loadedProfile) async {
    if (_savingProfile) return;
    setState(() => _savingProfile = true);
    final enteredKey = _apiKeyController.text.trim();
    final providerChanged =
        _loadedProvider != null && _loadedProvider != _provider;
    final hasReusableCredential =
        loadedProfile.hasCredential &&
        !providerChanged &&
        enteredKey == _storedCredentialMask;
    final replacementKey = hasReusableCredential ? '' : enteredKey;
    final hasProviderInput =
        _endpointController.text.trim().isNotEmpty ||
        _modelController.text.trim().isNotEmpty ||
        _targetLanguageController.text.trim().isNotEmpty ||
        replacementKey.isNotEmpty;
    if (!hasProviderInput && !hasReusableCredential) {
      try {
        final cleared = await ref
            .read(skillTranslationViewModelProvider.notifier)
            .clearProfile();
        if (cleared) {
          _apiKeyController.clear();
          ref
              .read(appNotificationControllerProvider.notifier)
              .success(AppNotificationMessage.translationSettingsSaved);
        }
      } finally {
        if (mounted) setState(() => _savingProfile = false);
      }
      return;
    }
    try {
      final saved = await ref
          .read(skillTranslationViewModelProvider.notifier)
          .saveProfile(
            _draftProfile(loadedProfile),
            replacementApiKey: replacementKey.isEmpty ? null : replacementKey,
            clearCredential:
                replacementKey.isEmpty &&
                (providerChanged ||
                    (loadedProfile.hasCredential && !hasReusableCredential)),
          );
      if (saved) {
        _apiKeyController.text =
            ref
                    .read(skillTranslationViewModelProvider)
                    .profile
                    ?.hasCredential ==
                true
            ? _storedCredentialMask
            : '';
        ref
            .read(appNotificationControllerProvider.notifier)
            .success(AppNotificationMessage.translationSettingsSaved);
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }
}

/// Typing into the masked stored key replaces it rather than appending to the
/// mask characters.
final _maskedKeyFormatter = TextInputFormatter.withFunction((
  oldValue,
  newValue,
) {
  if (oldValue.text != _storedCredentialMask ||
      newValue.text == oldValue.text) {
    return newValue;
  }
  final entered = newValue.text.replaceAll('•', '');
  return TextEditingValue(
    text: entered,
    selection: TextSelection.collapsed(offset: entered.length),
  );
});

String _sectionTitle(BuildContext context, SettingsSection section) =>
    switch (section) {
      SettingsSection.general => context.l10n.settingsGeneralTitle,
      SettingsSection.appearance => context.l10n.settingsAppearanceTitle,
      SettingsSection.agents => context.l10n.settingsAgentsTitle,
      SettingsSection.translation => context.l10n.translationSettingsTitle,
      SettingsSection.commandLine => context.l10n.settingsCommandLineTitle,
      SettingsSection.maintenance => context.l10n.settingsMaintenanceTitle,
      SettingsSection.about => context.l10n.settingsAboutSectionTitle,
    };

IconData _sectionIcon(SettingsSection section) => switch (section) {
  SettingsSection.general => LucideIcons.slidersHorizontal,
  SettingsSection.appearance => LucideIcons.palette,
  SettingsSection.agents => LucideIcons.bot,
  SettingsSection.translation => LucideIcons.languages,
  SettingsSection.commandLine => LucideIcons.terminal,
  SettingsSection.maintenance => LucideIcons.wrench,
  SettingsSection.about => LucideIcons.info,
};

class _SettingsSectionList extends StatelessWidget {
  const _SettingsSectionList({
    required this.selectedSection,
    required this.onSectionSelected,
  });

  final SettingsSection? selectedSection;
  final ValueChanged<SettingsSection> onSectionSelected;

  Widget _item(BuildContext context, SettingsSection section) =>
      SettingsNavItem(
        key: Key('settings-section-${section.id}'),
        label: _sectionTitle(context, section),
        icon: _sectionIcon(section),
        selected: section == selectedSection,
        onPressed: () => onSectionSelected(section),
      );

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('settings-section-list'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsNavGroup(
        label: context.l10n.settingsNavGroupApp,
        children: [
          _item(context, SettingsSection.appearance),
          _item(context, SettingsSection.general),
          _item(context, SettingsSection.agents),
          _item(context, SettingsSection.translation),
          _item(context, SettingsSection.commandLine),
        ],
      ),
      SettingsNavGroup(
        label: context.l10n.settingsNavGroupSystem,
        children: [
          _item(context, SettingsSection.maintenance),
          _item(context, SettingsSection.about),
        ],
      ),
    ],
  );
}

String _fingerprint(TranslationProviderProfile profile) =>
    profile.toJson().toString();

TranslationProviderProfile _translationDefaultsFor(
  AppTranslationProviderKind provider,
) => provider == AppTranslationProviderKind.openAICompatible
    ? TranslationProviderProfile.defaults()
    : const TranslationProviderProfile(
        provider: AppTranslationProviderKind.anthropic,
        endpoint: 'https://api.anthropic.com/v1',
        model: 'claude-sonnet-4-5',
        targetLanguage: 'zh-Hans',
      );

bool _isDefaultTranslationProfile(TranslationProviderProfile profile) {
  final defaults = _translationDefaultsFor(profile.provider);
  return profile.endpoint == defaults.endpoint &&
      profile.model == defaults.model &&
      profile.targetLanguage == defaults.targetLanguage &&
      profile.protocol == defaults.protocol &&
      profile.segmentCharacterBudget == defaults.segmentCharacterBudget &&
      profile.maxConcurrentSegments == defaults.maxConcurrentSegments &&
      profile.maxOutputTokens == defaults.maxOutputTokens &&
      profile.reasoningEnabled == defaults.reasoningEnabled;
}
