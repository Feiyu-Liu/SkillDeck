import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_link_opener.dart';
import 'package:skills_manager/features/skills/models/skill_source_link.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  SkillSourceLink link(String locator) => SkillSourceLink.fromSource(
    SkillSourceProvenance(kind: WorkspaceSourceKind.git, locator: locator),
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('launches the approved original URL in the external browser', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    expect(
      await const SkillSourceLinkOpener().open(
        link('https://example.com/repo'),
      ),
      isTrue,
    );
    expect(calls.single.method, 'launch');
    expect(calls.single.arguments['url'], 'https://example.com/repo');
    expect(calls.single.arguments['useWebView'], isFalse);
    expect(calls.single.arguments['useSafariVC'], isFalse);
  });

  test('never sends a rejected locator to the platform', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('must not launch'),
    );
    expect(
      await const SkillSourceLinkOpener().open(
        link('https://user:secret@example.com/repo'),
      ),
      isFalse,
    );
  });

  test('returns failure when the platform refuses or throws', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(
      await const SkillSourceLinkOpener().open(
        link('https://example.com/repo'),
      ),
      isFalse,
    );
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'failed', message: 'may contain a secret');
    });
    expect(
      await const SkillSourceLinkOpener().open(
        link('https://example.com/repo'),
      ),
      isFalse,
    );
  });
}
