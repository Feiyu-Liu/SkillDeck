import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';

enum CloudSignInPhase {
  signedOut,
  starting,
  waiting,
  denied,
  expired,
  failed,
  sessionCheckFailed,
  offline,
  signedIn,
  signingOut,
  signOutFailed,
}

final class CloudSignInState {
  const CloudSignInState._(
    this.phase, {
    this.account,
    this.userCode,
    this.browserOpenFailed = false,
  });

  final CloudSignInPhase phase;
  final CloudAccount? account;
  final String? userCode;
  final bool browserOpenFailed;

  CloudAccount? get verifiedAccount =>
      phase == CloudSignInPhase.signedIn ? account : null;
}

final cloudSignInViewModelProvider =
    AsyncNotifierProvider<CloudSignInViewModel, CloudSignInState>(
      CloudSignInViewModel.new,
    );

final class CloudSignInViewModel extends AsyncNotifier<CloudSignInState> {
  PendingSignIn? _pending;

  @override
  Future<CloudSignInState> build() async {
    ref.onDispose(() {
      _pending?.cancel();
      _pending = null;
    });
    return _readSession(ref.watch(cloudSignInProvider));
  }

  Future<void> refreshSession() async {
    final status = state.value?.phase;
    if (state.isLoading ||
        status == CloudSignInPhase.starting ||
        status == CloudSignInPhase.waiting ||
        status == CloudSignInPhase.signingOut) {
      return;
    }
    final signIn = ref.read(cloudSignInProvider);
    state = const AsyncLoading();
    final next = await _readSession(signIn);
    if (ref.mounted) state = AsyncData(next);
  }

  Future<CloudSignInState> _readSession(CloudSignIn? signIn) async {
    if (signIn == null) {
      return const CloudSignInState._(CloudSignInPhase.signedOut);
    }
    try {
      return switch (await signIn.currentSession()) {
        CloudSignedIn(:final account) => CloudSignInState._(
          CloudSignInPhase.signedIn,
          account: account,
        ),
        CloudSignInRequired() => const CloudSignInState._(
          CloudSignInPhase.signedOut,
        ),
        CloudSessionUnavailable(:final account) => CloudSignInState._(
          CloudSignInPhase.offline,
          account: account,
        ),
      };
    } on Object {
      // Platform exceptions and service data can include private details.
      return const CloudSignInState._(CloudSignInPhase.sessionCheckFailed);
    }
  }

  Future<void> startSignIn() async {
    final phase = state.value?.phase;
    if (phase != CloudSignInPhase.signedOut &&
        phase != CloudSignInPhase.denied &&
        phase != CloudSignInPhase.expired &&
        phase != CloudSignInPhase.failed) {
      return;
    }
    final signIn = ref.read(cloudSignInProvider);
    if (signIn == null) return;

    _set(CloudSignInPhase.starting);
    final readDevice = ref.read(cloudDeviceProvider);
    try {
      final device = await readDevice();
      if (!ref.mounted) return;
      final result = await signIn.start(device);
      if (result is! PendingSignIn) {
        _set(CloudSignInPhase.failed);
        return;
      }
      if (!ref.mounted) {
        result.cancel();
        return;
      }
      _pending = result;
      _set(CloudSignInPhase.waiting, userCode: result.userCode);
      switch (await signIn.complete(result)) {
        case CloudSignInSucceeded(:final account):
          _set(CloudSignInPhase.signedIn, account: account);
        case CloudSignInDenied():
          _set(CloudSignInPhase.denied);
        case CloudSignInExpired():
          _set(CloudSignInPhase.expired);
        case CloudSignInFailed():
          _set(CloudSignInPhase.failed);
        case CloudSignInCancelled():
          _set(CloudSignInPhase.signedOut);
      }
    } on Object {
      _set(CloudSignInPhase.failed);
    } finally {
      _pending = null;
    }
  }

  void cancelSignIn() => _pending?.cancel();

  Future<void> openVerificationPage() async {
    final pending = _pending;
    if (pending == null) return;
    var opened = false;
    try {
      opened = await ref.read(cloudBrowserLauncherProvider)(
        pending.verificationUriComplete,
      );
    } on Object {
      // Show a generic result in Settings without reporting the URL.
    }
    if (identical(_pending, pending)) {
      _set(
        CloudSignInPhase.waiting,
        userCode: pending.userCode,
        browserOpenFailed: !opened,
      );
    }
  }

  Future<void> signOut() async {
    final previous = state.value;
    if (previous == null ||
        (previous.phase != CloudSignInPhase.signedIn &&
            previous.phase != CloudSignInPhase.offline &&
            previous.phase != CloudSignInPhase.signOutFailed)) {
      return;
    }
    final signIn = ref.read(cloudSignInProvider);
    if (signIn == null) return;
    _set(CloudSignInPhase.signingOut, account: previous.account);
    try {
      await signIn.signOut();
      _set(CloudSignInPhase.signedOut);
    } on Object {
      _set(CloudSignInPhase.signOutFailed, account: previous.account);
    }
  }

  /// A 401 from the active sync runtime invalidates that account's session.
  Future<void> sessionExpired(String accountId) async {
    final account = state.value?.verifiedAccount;
    if (account?.id != accountId) return;
    final origin = ref.read(cloudOriginProvider);
    if (origin == null) return;
    final store = ref.read(cloudSessionStoreProvider);
    _set(CloudSignInPhase.signingOut, account: account);
    try {
      await store.delete(origin);
      _set(CloudSignInPhase.signedOut);
    } on Object {
      _set(CloudSignInPhase.signOutFailed, account: account);
    }
  }

  void _set(
    CloudSignInPhase phase, {
    CloudAccount? account,
    String? userCode,
    bool browserOpenFailed = false,
  }) {
    if (!ref.mounted) return;
    state = AsyncData(
      CloudSignInState._(
        phase,
        account: account,
        userCode: userCode,
        browserOpenFailed: browserOpenFailed,
      ),
    );
  }
}
