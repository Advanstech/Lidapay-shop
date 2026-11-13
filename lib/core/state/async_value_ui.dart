import 'package:flutter/material.dart';

/// Shared async-state wrapper so every API-bound screen handles
/// loading / error / data consistently.
sealed class AsyncValueUi<T> {
  const AsyncValueUi();
}

class LoadingUi<T> extends AsyncValueUi<T> {
  const LoadingUi();
}

class ErrorUi<T> extends AsyncValueUi<T> {
  const ErrorUi(this.message, {this.onRetry});
  final String message;
  final VoidCallback? onRetry;
}

class DataUi<T> extends AsyncValueUi<T> {
  const DataUi(this.data);
  final T data;
}
