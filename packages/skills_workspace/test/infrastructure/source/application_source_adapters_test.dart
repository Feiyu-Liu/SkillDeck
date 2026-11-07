import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/source/application_source_adapters.dart';
import 'package:test/test.dart';

void main() {
  test('Local bridge reuses normalized content and exact provenance', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'workspace-source-bridge-',
    );
    addTearDown(() async => temporary.delete(recursive: true));
    final skillDirectory = Directory(
      path.join(temporary.path, 'skills', 'review'),
    );
    await skillDirectory.create(recursive: true);
    await File(path.join(skillDirectory.path, 'SKILL.md')).writeAsString(
      '---\nname: Review\ndescription: Review description\n---\n',
    );
    final adapter = LocalApplicationSourceAdapter();

    final result = await adapter.acquireLocal(
      LocalSourceDescriptor(locator: temporary.path),
      selectedSkillNames: const {'Review'},
      options: const SourceAcquisitionOptions(),
      cancellationToken: CancellationToken.none(),
    );

    final skill = result.valueOrNull!.skills.single;
    expect(skill.slotKey, 'review');
    expect(skill.tree.files.single.relativePath, 'SKILL.md');
    expect(
      skill.provenance,
      LocalSourceDescriptor(
        locator: temporary.absolute.path,
        skillPath: 'skills/review',
      ),
    );
  });
}
