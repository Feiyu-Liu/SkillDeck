import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

final class RecordingAppDiagnosticSink implements AppDiagnosticSink {
  final List<AppDiagnosticEvent> events = [];

  @override
  void write(AppDiagnosticEvent event) => events.add(event);
}
