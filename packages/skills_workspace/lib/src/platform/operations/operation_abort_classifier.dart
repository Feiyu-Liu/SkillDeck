import 'dart:io';

import '../../application/operations/operation_models.dart';

/// The production [OperationAbortClassifier]: recognizes filesystem failures
/// in front of the infrastructure-free default.
///
/// Only the bounded [OperationAbortDetail] leaves this function; the error's
/// message and path never do.
OperationAbortDetail classifyPlatformOperationAbort(Object error) =>
    switch (error) {
      OperationAbortDetailSource() => classifyOperationAbort(error),
      IOException() => OperationAbortDetail.filesystem,
      _ => classifyOperationAbort(error),
    };
