import 'package:file_selector/file_selector.dart';

final class LoadedMarkdownDocument {
  const LoadedMarkdownDocument({
    required this.path,
    required this.content,
  });

  final String path;
  final String content;
}

abstract interface class MarkdownDocumentLoader {
  Future<LoadedMarkdownDocument?> pick();
}

final class FileSelectorMarkdownDocumentLoader
    implements MarkdownDocumentLoader {
  const FileSelectorMarkdownDocumentLoader();

  @override
  Future<LoadedMarkdownDocument?> pick() async {
    const typeGroup = XTypeGroup(
      label: 'Markdown',
      extensions: <String>['md'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (file == null) {
      return null;
    }
    try {
      return LoadedMarkdownDocument(
        path: file.path,
        content: await file.readAsString(),
      );
    } on Object {
      throw const MarkdownDocumentLoadException(
        'The selected Markdown file could not be read.',
      );
    }
  }
}

final class MarkdownDocumentLoadException implements Exception {
  const MarkdownDocumentLoadException(this.message);

  final String message;
}
