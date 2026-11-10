import 'package:file_selector/file_selector.dart';

abstract interface class DirectoryPicker {
  Future<String?> pickDirectory({String? initialDirectory});
}

final class NativeDirectoryPicker implements DirectoryPicker {
  @override
  Future<String?> pickDirectory({String? initialDirectory}) => getDirectoryPath(
    initialDirectory: initialDirectory,
    confirmButtonText: 'Select',
  );
}
