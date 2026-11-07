import 'package:skills_manager/features/skills/data/services/directory_picker.dart';

final class FakeDirectoryPicker implements DirectoryPicker {
  FakeDirectoryPicker(this.path);

  String? path;
  int calls = 0;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async {
    calls += 1;
    return path;
  }
}
