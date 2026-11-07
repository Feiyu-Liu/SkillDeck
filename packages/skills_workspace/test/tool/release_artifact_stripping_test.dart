import 'dart:typed_data';

import 'package:test/test.dart';

import '../../tool/release_artifact_stripping.dart';

void main() {
  group('ReleaseArtifactStrippingOptions', () {
    test('parses artifact, bundle, and report paths', () {
      final options = ReleaseArtifactStrippingOptions.parse(const <String>[
        '--artifact',
        '/release/native',
        '--bundle',
        '/release/app',
        '--report',
        '/release/evidence.json',
      ]);

      expect(options.artifactPath, '/release/native');
      expect(options.bundlePath, '/release/app');
      expect(options.reportPath, '/release/evidence.json');
    });

    test('rejects missing values and unknown options', () {
      expect(
        () => ReleaseArtifactStrippingOptions.parse(const <String>[]),
        throwsFormatException,
      );
      expect(
        () =>
            ReleaseArtifactStrippingOptions.parse(const <String>['--artifact']),
        throwsFormatException,
      );
      expect(
        () => ReleaseArtifactStrippingOptions.parse(const <String>[
          '--binary',
          '/release/native',
        ]),
        throwsFormatException,
      );
    });
  });

  group('native debug metadata parsers', () {
    test('finds Mach-O debug sections and local symbols', () {
      expect(
        parseMachODebugSections('''
          sectname __text
          sectname __debug_info
          sectname __debug_line
'''),
        {'__debug_info', '__debug_line'},
      );
      expect(
        parseMachOLocalSymbols('''
0000000100001000 (__TEXT,__text) non-external _private_function
0000000100002000 (__TEXT,__text) external _public_function
                 (undefined) external _malloc (from libSystem)
'''),
        ['0000000100001000 (__TEXT,__text) non-external _private_function'],
      );
    });

    test('finds ELF static symbols and debug sections', () {
      expect(
        parseElfDebugOrStaticSymbolSections('''
  [ 1] .dynsym           DYNSYM
  [12] .debug_info       PROGBITS
  [13] .gnu_debuglink    PROGBITS
  [14] .symtab           SYMTAB
'''),
        {'.debug_info', '.gnu_debuglink', '.symtab'},
      );
    });

    test('reads the PE COFF symbol-table fields', () {
      final stripped = _pe(pointer: 0, count: 0);
      final unstripped = _pe(pointer: 0x800, count: 42);

      expect(parsePeCoffSymbolTable(stripped).isAbsent, isTrue);
      expect(parsePeCoffSymbolTable(unstripped).isAbsent, isFalse);
      expect(parsePeCoffSymbolTable(unstripped).pointer, 0x800);
      expect(parsePeCoffSymbolTable(unstripped).symbolCount, 42);
    });

    test('recognizes platform debug companions', () {
      expect(isNativeDebugCompanionPath('/App/native.framework.dSYM'), isTrue);
      expect(isNativeDebugCompanionPath(r'C:\App\native.pdb'), isTrue);
      expect(isNativeDebugCompanionPath('/App/lib/native.debug'), isTrue);
      expect(isNativeDebugCompanionPath('/App/native.dll'), isFalse);
    });
  });

  group('stripped artifact policy', () {
    test('accepts stripped facts on all desktop formats', () {
      validateStrippedReleaseArtifact(
        platform: ReleaseArtifactPlatform.macOS,
        artifactPath: '/release/native',
        facts: const ReleaseArtifactStrippingFacts(),
      );
      validateStrippedReleaseArtifact(
        platform: ReleaseArtifactPlatform.linux,
        artifactPath: '/release/native.so',
        facts: const ReleaseArtifactStrippingFacts(),
      );
      validateStrippedReleaseArtifact(
        platform: ReleaseArtifactPlatform.windows,
        artifactPath: r'C:\release\native.dll',
        facts: const ReleaseArtifactStrippingFacts(
          peCoffSymbolTable: PeCoffSymbolTable(pointer: 0, symbolCount: 0),
        ),
      );
    });

    test(
      'rejects debug sections, local symbols, COFF symbols, and sidecars',
      () {
        expect(
          () => validateStrippedReleaseArtifact(
            platform: ReleaseArtifactPlatform.macOS,
            artifactPath: '/release/native',
            facts: const ReleaseArtifactStrippingFacts(
              localSymbols: <String>['_private'],
            ),
          ),
          throwsA(isA<ReleaseArtifactStrippingException>()),
        );
        expect(
          () => validateStrippedReleaseArtifact(
            platform: ReleaseArtifactPlatform.linux,
            artifactPath: '/release/native.so',
            facts: const ReleaseArtifactStrippingFacts(
              debugSections: <String>{'.symtab'},
            ),
          ),
          throwsA(isA<ReleaseArtifactStrippingException>()),
        );
        expect(
          () => validateStrippedReleaseArtifact(
            platform: ReleaseArtifactPlatform.windows,
            artifactPath: r'C:\release\native.dll',
            facts: const ReleaseArtifactStrippingFacts(
              peCoffSymbolTable: PeCoffSymbolTable(
                pointer: 1024,
                symbolCount: 1,
              ),
            ),
          ),
          throwsA(isA<ReleaseArtifactStrippingException>()),
        );
        expect(
          () => validateStrippedReleaseArtifact(
            platform: ReleaseArtifactPlatform.macOS,
            artifactPath: '/release/native',
            facts: const ReleaseArtifactStrippingFacts(
              debugCompanions: <String>['/release/native.dSYM'],
            ),
          ),
          throwsA(isA<ReleaseArtifactStrippingException>()),
        );
      },
    );
  });
}

Uint8List _pe({required int pointer, required int count}) {
  final bytes = Uint8List(256);
  bytes[0] = 0x4d;
  bytes[1] = 0x5a;
  final data = ByteData.sublistView(bytes);
  data.setUint32(0x3c, 0x80, Endian.little);
  bytes[0x80] = 0x50;
  bytes[0x81] = 0x45;
  data.setUint32(0x8c, pointer, Endian.little);
  data.setUint32(0x90, count, Endian.little);
  return bytes;
}
