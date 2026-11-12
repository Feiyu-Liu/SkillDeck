import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/self_update/data/app_update_configuration.dart';

/// Supplied by Windows bootstrap; Sparkle owns application termination on macOS.
final windowsQuitRequestProvider = Provider<AsyncCallback?>((ref) => null);

final appUpdateConfigurationProvider =
    Provider<AsyncValue<AppUpdateConfiguration?>>((ref) {
      try {
        return AsyncData(loadAppUpdateConfiguration());
      } on Object catch (error, stackTrace) {
        return AsyncError(error, stackTrace);
      }
    });

final appUpdateCoordinatorProvider = Provider<AppUpdateCoordinator?>((ref) {
  if (!Platform.isMacOS && !Platform.isWindows) return null;
  final configuration = ref
      .watch(appUpdateConfigurationProvider)
      .when(data: (value) => value, error: (_, _) => null, loading: () => null);
  if (configuration == null) return null;

  final coordinator = AppUpdateCoordinator(
    configuration: configuration,
    onQuitForUpdate: Platform.isWindows
        ? ref.watch(windowsQuitRequestProvider)
        : null,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// The version this build was released as, set by the release configuration.
const appVersion = String.fromEnvironment(
  'SKILLDECK_VERSION',
  defaultValue: '1.0.0',
);

/// Immutable installed comparison identity generated from release version/build.
/// Empty in development; a configured Windows updater fails closed without it.
const appBuildVersion = String.fromEnvironment('SKILLDECK_BUILD_VERSION');

final appVersionProvider = Provider<AsyncValue<String>>(
  (ref) => const AsyncData(appVersion),
);

const _defaultUpdateCheckTimeout = Duration(seconds: 30);

sealed class AppUpdateState {
  const AppUpdateState();
}

enum _UpdateRequestKind { background, foreground }

final class AppUpdateIdle extends AppUpdateState {
  const AppUpdateIdle();
}

final class AppUpdateChecking extends AppUpdateState {
  const AppUpdateChecking();
}

final class AppUpdateAvailable extends AppUpdateState {
  const AppUpdateAvailable(this.version);

  final String? version;
}

final class AppUpdateDownloaded extends AppUpdateState {
  const AppUpdateDownloaded(this.version);

  final String? version;
}

final class AppUpdateFailed extends AppUpdateState {
  const AppUpdateFailed();
}

final class AppUpdateCoordinator extends ChangeNotifier with UpdaterListener {
  AppUpdateCoordinator({
    required this.configuration,
    this.onQuitForUpdate,
    String installedReleaseVersion = appBuildVersion,
    bool? isWindows,
    Duration checkTimeout = _defaultUpdateCheckTimeout,
  }) : _platform = null,
       _installedReleaseVersion = installedReleaseVersion,
       _isWindows = isWindows ?? Platform.isWindows,
       _checkTimeout = checkTimeout {
    autoUpdater.addListener(this);
  }

  @visibleForTesting
  AppUpdateCoordinator.forTesting({
    required AutoUpdaterPlatform platform,
    this.onQuitForUpdate,
    AppUpdateConfiguration? configuration,
    String installedReleaseVersion = appBuildVersion,
    bool isWindows = false,
    Duration checkTimeout = _defaultUpdateCheckTimeout,
  }) : configuration =
           configuration ??
           AppUpdateConfiguration(
             feedUrl: Uri.parse('https://updates.example.com/appcast.xml'),
           ),
       _platform = platform,
       _installedReleaseVersion = installedReleaseVersion,
       _isWindows = isWindows,
       _checkTimeout = checkTimeout {
    _platformSubscription = platform.sparkleEvents.listen(_handlePlatformEvent);
  }

  final AppUpdateConfiguration configuration;
  final AsyncCallback? onQuitForUpdate;
  final AutoUpdaterPlatform? _platform;
  final String _installedReleaseVersion;
  final bool _isWindows;
  final Duration _checkTimeout;
  StreamSubscription<Map<Object?, Object?>>? _platformSubscription;
  Timer? _checkTimeoutTimer;
  AppUpdateState state = const AppUpdateIdle();
  bool _initialized = false;
  bool _initializing = false;
  bool _requestInFlight = false;
  _UpdateRequestKind? _activeRequest;
  bool _disposed = false;
  bool _quitRequested = false;
  // The prompt a check started from. While that check is in flight the prompt
  // stays visible as a busy control instead of vanishing until the native
  // updater answers, and a check the user cancels returns to it.
  AppUpdateState? _promptBeforeCheck;

  bool get isConfigured => true;
  bool get hasUpdatePrompt =>
      _isPrompt(state) ||
      (state is AppUpdateChecking && _promptBeforeCheck != null);

  /// Configures the native updater without starting a check of its own.
  ///
  /// Starting the native updater lets it run a scheduled check that is due,
  /// and a second check issued here would be rejected while that session is
  /// in progress. The native scheduler therefore owns every background check.
  Future<void> initialize({bool reportFailure = false}) async {
    if (_initialized || _initializing || _disposed) return;
    _initializing = true;
    try {
      final platform = _platform;
      if (_isWindows) {
        if (!RegExp(r'^\d+\.\d+\.\d+\+\d+$')
            .hasMatch(_installedReleaseVersion)) {
          throw StateError(
            'A Windows updater requires its installed release identity.',
          );
        }
        if (platform != null) {
          await platform.setAppBuildVersion(_installedReleaseVersion);
        } else {
          await autoUpdater.setAppBuildVersion(_installedReleaseVersion);
        }
      }
      if (platform != null) {
        await platform.setScheduledCheckInterval(
          configuration.checkInterval.inSeconds,
        );
        await platform.setFeedURL(configuration.feedUrl.toString());
      } else {
        await autoUpdater.setScheduledCheckInterval(
          configuration.checkInterval.inSeconds,
        );
        await autoUpdater.setFeedURL(configuration.feedUrl.toString());
      }
      _initialized = true;
    } on Object {
      if (reportFailure) _setState(const AppUpdateFailed());
    } finally {
      _initializing = false;
    }
  }

  Future<UpdateCheckStart?> checkForUpdates({bool inBackground = false}) async {
    if (_disposed) return null;
    if (_requestInFlight || _activeRequest != null) {
      return UpdateCheckStart.busy;
    }
    await initialize(reportFailure: !inBackground);
    if (!_initialized) return null;
    if (_requestInFlight || _activeRequest != null) {
      return UpdateCheckStart.busy;
    }
    _requestInFlight = true;
    _activeRequest = inBackground
        ? _UpdateRequestKind.background
        : _UpdateRequestKind.foreground;
    // Recorded before the transition so listeners never see a frame in
    // which the prompt has disappeared.
    _promptBeforeCheck = _isPrompt(state) ? state : null;
    _setState(const AppUpdateChecking());
    _checkTimeoutTimer?.cancel();
    _checkTimeoutTimer = Timer(_checkTimeout, _handleCheckTimeout);
    final UpdateCheckStart start;
    try {
      final platform = _platform;
      start = platform != null
          ? await platform.checkForUpdates(inBackground: inBackground)
          : await autoUpdater.checkForUpdates(inBackground: inBackground);
    } on Object {
      _finishRequest(failed: !inBackground);
      return null;
    } finally {
      _requestInFlight = false;
    }
    // A native session already in progress either rejected this check or
    // brought the update it shows into focus. That session's own events still
    // update the state, so this request has nothing left to wait for.
    if (start != UpdateCheckStart.started) _returnToStateBeforeCheck();
    return start;
  }

  Future<UpdateCheckStart?> openUpdateDialog({required bool blocked}) async {
    if (blocked) return null;
    return checkForUpdates();
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    _finishRequest(failed: _activeRequest == _UpdateRequestKind.foreground);
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    if (_requestInFlight) _setState(const AppUpdateChecking());
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    _setState(AppUpdateAvailable(_versionOf(appcastItem)));
    _finishRequest();
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _setState(const AppUpdateIdle());
    _finishRequest();
  }

  @override
  void onUpdaterUpdateFinished(UpdaterError? error) {
    final request = _activeRequest;
    if (request == null) return;

    _finishRequest(
      failed:
          state is AppUpdateChecking &&
          request == _UpdateRequestKind.foreground &&
          error != null,
    );
  }

  @override
  void onUpdaterUpdateCancelled() => _returnToStateBeforeCheck();

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _setState(AppUpdateDownloaded(_versionOf(appcastItem)));
    _finishRequest();
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    if (_disposed) return;
    _setState(AppUpdateDownloaded(_versionOf(appcastItem)));
    _finishRequest();
    final quit = onQuitForUpdate;
    if (quit != null && !_quitRequested) {
      _quitRequested = true;
      unawaited(quit());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _checkTimeoutTimer?.cancel();
    _checkTimeoutTimer = null;
    if (_platform == null) autoUpdater.removeListener(this);
    unawaited(_platformSubscription?.cancel());
    super.dispose();
  }

  void _handlePlatformEvent(Map<Object?, Object?> event) {
    switch (event['type']) {
      case 'error':
        onUpdaterError(_errorFromPlatformEvent(event));
      case 'checking-for-update':
        onUpdaterCheckingForUpdate(null);
      case 'update-available':
        onUpdaterUpdateAvailable(null);
      case 'update-not-available':
        onUpdaterUpdateNotAvailable(null);
      case 'update-finished':
        onUpdaterUpdateFinished(_errorFromPlatformEvent(event));
      case 'update-downloaded':
        onUpdaterUpdateDownloaded(null);
      case 'before-quit-for-update':
        onUpdaterBeforeQuitForUpdate(null);
      case 'update-cancelled':
        onUpdaterUpdateCancelled();
    }
  }

  UpdaterError? _errorFromPlatformEvent(Map<Object?, Object?> event) {
    final value = event['error'];
    return value == null ? null : UpdaterError(value.toString());
  }

  void _setState(AppUpdateState value) {
    if (_disposed) return;
    if (value is! AppUpdateChecking) _promptBeforeCheck = null;
    if (state.runtimeType == value.runtimeType) {
      if (state is AppUpdateAvailable && value is AppUpdateAvailable) {
        if ((state as AppUpdateAvailable).version == value.version) return;
      } else if (state is AppUpdateDownloaded &&
          value is AppUpdateDownloaded &&
          (state as AppUpdateDownloaded).version == value.version) {
        return;
      } else {
        return;
      }
    }
    state = value;
    notifyListeners();
  }

  void _handleCheckTimeout() {
    if (_activeRequest == null || _disposed) return;
    _finishRequest(failed: _activeRequest == _UpdateRequestKind.foreground);
  }

  void _returnToStateBeforeCheck() {
    if (state is AppUpdateChecking) {
      _setState(_promptBeforeCheck ?? const AppUpdateIdle());
    }
    _finishRequest();
  }

  void _finishRequest({bool failed = false}) {
    if (_activeRequest == null && _checkTimeoutTimer == null) return;
    final wasChecking = state is AppUpdateChecking;
    _checkTimeoutTimer?.cancel();
    _checkTimeoutTimer = null;
    _activeRequest = null;
    if (failed) {
      _setState(const AppUpdateFailed());
    } else if (wasChecking) {
      _setState(const AppUpdateIdle());
    }
  }
}

bool _isPrompt(AppUpdateState state) =>
    state is AppUpdateAvailable ||
    state is AppUpdateDownloaded ||
    state is AppUpdateFailed;

String? _versionOf(AppcastItem? item) =>
    item?.displayVersionString ?? item?.versionString;
