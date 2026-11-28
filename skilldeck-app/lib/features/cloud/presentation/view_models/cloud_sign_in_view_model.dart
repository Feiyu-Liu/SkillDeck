import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';

enum CloudSignInPhase {
  signedOut,
  signingIn,
  failed,
  sessionCheckFailed,
  offline,
  signedIn,
  signingOut,
  signOutFailed,
}

enum CloudSignInFailure { network, busy, other }

final class CloudSignInState {
  const CloudSignInState._(
    this.phase, {
    this.account,
    this.failure,
    this.explicitSignIn = false,
  });

  final CloudSignInPhase phase;
  final CloudAccount? account;
  final CloudSignInFailure? failure;
  final bool explicitSignIn;

  CloudAccount? get verifiedAccount =>
      phase == CloudSignInPhase.signedIn ? account : null;
}

final cloudSignInViewModelProvider =
    AsyncNotifierProvider<CloudSignInViewModel, CloudSignInState>(
      CloudSignInViewModel.new,
    );

final class CloudSignInViewModel extends AsyncNotifier<CloudSignInState> {
  @override
  Future<CloudSignInState> build() async {
    return _readSession(ref.watch(cloudSignInProvider));
  }

  Future<void> refreshSession() async {
    final status = state.value?.phase;
    if (state.isLoading ||
        status == CloudSignInPhase.signingIn ||
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
        phase != CloudSignInPhase.failed) {
      return;
    }
    final signIn = ref.read(cloudSignInProvider);
    if (signIn == null) return;
    _set(CloudSignInPhase.signingIn);
    final readDevice = ref.read(cloudDeviceProvider);
    final authenticator = ref.read(cloudWebAuthenticatorProvider);
    try {
      final device = await readDevice();
      if (!ref.mounted) return;
      switch (await signIn.signInWithBrowser(device, authenticator)) {
        case CloudSignInSucceeded(:final account):
          _set(
            CloudSignInPhase.signedIn,
            account: account,
            explicitSignIn: true,
          );
        case CloudSignInCancelled() || CloudSignInDenied():
          _set(CloudSignInPhase.signedOut);
        case CloudSignInFailed(:final code):
          _set(
            CloudSignInPhase.failed,
            failure: switch (code) {
              CloudFailureCode.network => CloudSignInFailure.network,
              CloudFailureCode.server => CloudSignInFailure.busy,
              CloudFailureCode.protocol => CloudSignInFailure.other,
            },
          );
        case CloudSignInExpired():
          _set(CloudSignInPhase.failed, failure: CloudSignInFailure.other);
      }
    } on Object {
      _set(CloudSignInPhase.failed, failure: CloudSignInFailure.other);
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
    CloudSignInFailure? failure,
    bool explicitSignIn = false,
  }) {
    if (!ref.mounted) return;
    state = AsyncData(
      CloudSignInState._(
        phase,
        account: account,
        failure: failure,
        explicitSignIn: explicitSignIn,
      ),
    );
  }
}
