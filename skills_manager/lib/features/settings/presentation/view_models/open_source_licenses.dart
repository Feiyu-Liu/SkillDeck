import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One component named in the open source licenses list, with every license
/// text that names it.
@immutable
final class OpenSourceLicensePackage {
  const OpenSourceLicensePackage({required this.name, required this.licenses});

  final String name;
  final List<LicenseEntry> licenses;
}

/// Every license registered with Flutter's [LicenseRegistry], grouped by the
/// package it names and sorted by name.
///
/// The registry streams one entry per license text. An entry that names
/// several packages is listed under each of them, as Flutter's own license
/// page does. The result is kept for the life of the process because
/// collecting the registry parses every bundled license text.
final openSourceLicensesProvider =
    FutureProvider<List<OpenSourceLicensePackage>>((ref) async {
      final byPackage = <String, List<LicenseEntry>>{};
      await for (final entry in LicenseRegistry.licenses) {
        for (final package in entry.packages) {
          (byPackage[package] ??= []).add(entry);
        }
      }
      final packages = [
        for (final MapEntry(key: name, value: licenses) in byPackage.entries)
          OpenSourceLicensePackage(
            name: name,
            licenses: List.unmodifiable(licenses),
          ),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return List.unmodifiable(packages);
    });
