import '../sign_in/cloud_sign_in.dart';
import 'cloud_values.dart';

sealed class CloudApiResult<T> {
  const CloudApiResult();
}

final class CloudApiSuccess<T> extends CloudApiResult<T> {
  const CloudApiSuccess(this.value, {this.retryAfter});
  final T value;
  final Duration? retryAfter;
}

sealed class CloudApiError extends CloudApiResult<Never> {
  const CloudApiError();
}

final class ApiSignInRequired extends CloudApiError {
  const ApiSignInRequired();
}

final class ApiStorageLimitReached extends CloudApiError {
  const ApiStorageLimitReached();
}

final class ApiUnavailable extends CloudApiError {
  const ApiUnavailable(this.code, {this.retryAfter});
  final CloudFailureCode code;
  final Duration? retryAfter;
}

final class ApiInvalidRequest extends CloudApiError {
  const ApiInvalidRequest();
}

final class ApiNotFound extends CloudApiError {
  const ApiNotFound();
}

final class ApiCursorExpired extends CloudApiError {
  const ApiCursorExpired();
}

final class ApiStaleHead extends CloudApiError {
  const ApiStaleHead(this.lineage);
  final Lineage lineage;
}

final class ApiWrongGeneration extends CloudApiError {
  const ApiWrongGeneration({this.lineage, required this.generation});
  final Lineage? lineage;
  final int generation;
}

final class ApiLineageEnded extends CloudApiError {
  const ApiLineageEnded([this.lineage]);
  final Lineage? lineage;
}

final class ApiPackMissing extends CloudApiError {
  const ApiPackMissing();
}

final class ApiPackLacksHead extends CloudApiError {
  const ApiPackLacksHead();
}

final class ApiNotDescendant extends CloudApiError {
  const ApiNotDescendant();
}

enum PackSizeLimit { packed, inflated }

final class ApiPackTooLarge extends CloudApiError {
  const ApiPackTooLarge(this.limit);
  final PackSizeLimit limit;
}

enum PackRejectionReason {
  digestMismatch,
  packChecksum,
  packFormat,
  missingRoot,
  missingObject,
}

final class ApiPackRejected extends CloudApiError {
  const ApiPackRejected(this.reason);
  final PackRejectionReason reason;
}
