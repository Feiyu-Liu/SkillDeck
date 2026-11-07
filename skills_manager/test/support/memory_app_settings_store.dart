import 'dart:convert';

import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';

class MemoryAppSettingsStore implements AppSettingsStore {
  MemoryAppSettingsStore([this.value = const AppSettings()]);
  AppSettings? value;
  bool failWrites = false;
  @override
  Future<AppSettings?> read() async => value;
  @override
  Future<void> write(AppSettings settings) async {
    if (failWrites) throw StateError('write failed');
    value = settings;
  }

  @override
  Future<AppSettingsStoreSnapshot> captureSnapshot() async => value == null
      ? const AppSettingsStoreSnapshot.missing()
      : AppSettingsStoreSnapshot.withValue(_encode());
  String _encode() => jsonEncode(value!.toJson());
  @override
  Future<void> restore(AppSettingsStoreSnapshot snapshot) async {
    value = snapshot.rawValue == null
        ? null
        : AppSettings.decode(snapshot.rawValue!);
  }
}
