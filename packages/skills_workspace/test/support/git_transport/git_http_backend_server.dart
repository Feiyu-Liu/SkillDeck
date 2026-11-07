import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A loopback smart-HTTP Git server for transport tests.
///
/// Each request runs `git http-backend` as a CGI process against
/// [projectRoot], so clients exercise the real smart protocol, including
/// shallow fetch, without any network access. When [requireAuthentication]
/// is set, every request is answered with `401` to model a private
/// repository.
final class GitHttpBackendServer {
  GitHttpBackendServer._(this._server, this.projectRoot);

  final HttpServer _server;
  final String projectRoot;

  /// Number of requests served, for asserting that a client never connected.
  int requestCount = 0;

  static Future<GitHttpBackendServer> start({
    required String projectRoot,
    bool requireAuthentication = false,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final backend = GitHttpBackendServer._(server, projectRoot);
    server.listen((request) async {
      backend.requestCount += 1;
      try {
        if (requireAuthentication) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..headers.set('WWW-Authenticate', 'Basic realm="fixture"');
          await request.response.close();
          return;
        }
        await backend._serve(request);
      } on Object {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } on Object {
          // The client may already have disconnected.
        }
      }
    });
    return backend;
  }

  /// The HTTP locator for a repository directory beneath [projectRoot].
  String locatorFor(String relativeRepository) =>
      'http://127.0.0.1:${_server.port}/$relativeRepository';

  Future<void> close() => _server.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    final body = BytesBuilder(copy: false);
    await request.forEach(body.add);
    final environment = <String, String>{
      'PATH': Platform.environment['PATH'] ?? '',
      if (Platform.isWindows)
        'SystemRoot': Platform.environment['SystemRoot'] ?? '',
      'GIT_PROJECT_ROOT': projectRoot,
      'GIT_HTTP_EXPORT_ALL': '1',
      'GATEWAY_INTERFACE': 'CGI/1.1',
      'REQUEST_METHOD': request.method,
      'PATH_INFO': request.uri.path,
      'QUERY_STRING': request.uri.query,
      'REMOTE_ADDR': '127.0.0.1',
      'CONTENT_LENGTH': '${body.length}',
      'CONTENT_TYPE': ?request.headers.value(HttpHeaders.contentTypeHeader),
      'HTTP_CONTENT_ENCODING': ?request.headers.value(
        HttpHeaders.contentEncodingHeader,
      ),
      'HTTP_GIT_PROTOCOL': ?request.headers.value('git-protocol'),
    };
    final process = await Process.start(
      'git',
      const <String>['http-backend'],
      environment: environment,
      includeParentEnvironment: false,
    );
    final stdout = BytesBuilder(copy: false);
    final collected = process.stdout.forEach(stdout.add);
    final drained = process.stderr.drain<void>();
    process.stdin.add(body.takeBytes());
    await process.stdin.close();
    await Future.wait<void>([collected, drained]);
    await process.exitCode;
    _writeCgiResponse(stdout.takeBytes(), request.response);
    await request.response.close();
  }
}

void _writeCgiResponse(Uint8List output, HttpResponse response) {
  var headerEnd = -1;
  var separatorLength = 0;
  for (var index = 0; index < output.length - 1; index += 1) {
    if (output[index] == 0x0a && output[index + 1] == 0x0a) {
      headerEnd = index;
      separatorLength = 2;
      break;
    }
    if (index + 3 < output.length &&
        output[index] == 0x0d &&
        output[index + 1] == 0x0a &&
        output[index + 2] == 0x0d &&
        output[index + 3] == 0x0a) {
      headerEnd = index;
      separatorLength = 4;
      break;
    }
  }
  if (headerEnd < 0) {
    response.statusCode = HttpStatus.badGateway;
    return;
  }
  final headers = latin1.decode(output.sublist(0, headerEnd));
  for (final line in const LineSplitter().convert(headers)) {
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final name = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    if (name.toLowerCase() == 'status') {
      response.statusCode = int.parse(value.split(' ').first);
    } else {
      response.headers.set(name, value);
    }
  }
  response.add(output.sublist(headerEnd + separatorLength));
}
