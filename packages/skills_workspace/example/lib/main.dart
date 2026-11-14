// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';

Future<void> main() async {
  if (Platform.environment['SKILLS_WORKSPACE_RELEASE_SMOKE'] == '1') {
    try {
      stdout.writeln(await verifyNativePackageLoading());
      await stdout.flush();
      exit(0);
    } on Object {
      stderr.writeln('Native revision engine release smoke failed.');
      await stderr.flush();
      exit(1);
    }
  }
  runApp(const SkillsWorkspaceExample());
}

final class SkillsWorkspaceExample extends StatefulWidget {
  const SkillsWorkspaceExample({super.key, this.status});

  final Future<String>? status;

  @override
  State<SkillsWorkspaceExample> createState() => _SkillsWorkspaceExampleState();
}

final class _SkillsWorkspaceExampleState extends State<SkillsWorkspaceExample> {
  late final Future<String> _status;

  @override
  void initState() {
    super.initState();
    _status = widget.status ?? verifyNativePackageLoading();
  }

  @override
  Widget build(BuildContext context) {
    final slotKey = deriveSlotKey('Example Skill').valueOrNull;
    return CupertinoApp(
      home: CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Skills Workspace'),
        ),
        child: SafeArea(
          child: Center(
            child: FutureBuilder<String>(
              future: _status,
              builder: (context, snapshot) {
                final status = snapshot.hasError
                    ? 'Native revision engine unavailable'
                    : snapshot.data ?? 'Loading native revision engine…';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(status, key: const ValueKey('native-status')),
                    const SizedBox(height: 8),
                    Text('Derived Slot Key: $slotKey'),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

Future<String> verifyNativePackageLoading() async {
  final root = await Directory.systemTemp.createTemp(
    'skills-workspace-example-',
  );
  final engine = RevisionNativeEngine.open();
  try {
    engine.createStore('${root.path}${Platform.pathSeparator}store.git');
    final version = engine.version();
    return 'Native revision engine ready · libgit2 $version';
  } finally {
    engine.close();
    await root.delete(recursive: true);
  }
}
