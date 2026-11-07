import 'package:llm_dart_transport/llm_dart_transport.dart';

/// Creates an SDK transport with retries and all SDK logging disabled.
TransportClient createTranslationTransport() {
  final logger = Logger.detached('skills_translation.llm_transport')
    ..level = Level.OFF;
  return DioTransportClient(
    logger: logger,
    retryPolicy: const TransportRetryPolicy(maxAttempts: 1),
  );
}
