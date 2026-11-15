import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:skills_cloud/skills_cloud.dart';

/// Reports the SDK's physical stalled-TLS cleanup separately from client tests.
Future<void> main() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  final closed = Completer<void>();
  server.listen((socket) {
    sockets.add(socket);
    socket.listen(
      (_) {},
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
      onError: (Object _) {
        if (!closed.isCompleted) closed.complete();
      },
    );
  });
  final transport = HttpsCloudTransport(
    baseUri: Uri.parse('https://127.0.0.1:${server.port}'),
    timeout: const Duration(milliseconds: 100),
  );
  var deadlineReturned = false, physicallyClosed = false;
  try {
    try {
      await transport.request(
        CloudRequest(method: 'GET', path: '/v1/tls-qualification'),
      );
    } on CloudException catch (error) {
      deadlineReturned = error.code == CloudErrorCode.timeout;
    }
    try {
      await closed.future.timeout(const Duration(milliseconds: 300));
      physicallyClosed = true;
    } on TimeoutException {
      /* Known SDK behavior; never report it as a pass. */
    }
    stdout.writeln(
      jsonEncode({
        'dartVersion': Platform.version.split(' ').first,
        'requestDeadlineReturned': deadlineReturned,
        'pendingTLSPhysicallyClosed': physicallyClosed,
        'result': deadlineReturned && physicallyClosed
            ? 'passed'
            : 'knownSdkLimitation',
      }),
    );
    if (!deadlineReturned || !physicallyClosed) exitCode = 2;
  } finally {
    transport.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}
