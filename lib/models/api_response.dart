import 'dart:convert';
import 'package:http/http.dart' as http;

/// Represents a standardized server or local operation response.
class ApiResponse<T> {
  final bool success;
  final int? statusCode;
  final String? message;
  final T? data;
  final bool isOffline;

  const ApiResponse({
    required this.success,
    this.statusCode,
    this.message,
    this.data,
    this.isOffline = false,
  });

  /// Const constructor for a successful API response
  const ApiResponse.success(this.data, {this.statusCode = 200, this.message})
      : success = true,
        isOffline = false;

  /// Const constructor for a failed API response
  const ApiResponse.error({this.statusCode, this.message, this.isOffline = false, this.data})
      : success = false;

  /// Factory to parse standard HTTP response
  factory ApiResponse.fromHttpResponse(
    http.Response response, {
    T Function(dynamic json)? parser,
    String? defaultErrorMessage,
  }) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    String? extractedMessage;
    T? parsedData;

    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          extractedMessage = decoded['error']?.toString() ??
              decoded['message']?.toString() ??
              decoded['reason']?.toString();
          if (isSuccess && parser != null) {
            parsedData = parser(decoded);
          }
        } else if (isSuccess && parser != null) {
          parsedData = parser(decoded);
        }
      } catch (_) {
        if (!isSuccess && response.body.length < 200) {
          extractedMessage = response.body;
        }
      }
    }

    if (isSuccess) {
      return ApiResponse<T>.success(
        parsedData,
        statusCode: response.statusCode,
        message: extractedMessage,
      );
    } else {
      final reason = response.reasonPhrase ?? '';
      final msg = extractedMessage ??
          (reason.isNotEmpty ? reason : defaultErrorMessage ?? 'Request failed');
      return ApiResponse<T>.error(
        statusCode: response.statusCode,
        message: msg,
      );
    }
  }

  /// Human-friendly feedback summary with HTTP status code
  String formatFeedback({String? actionName}) {
    final prefix = actionName != null ? '$actionName: ' : '';
    if (success) {
      final statusInfo = statusCode != null ? ' (HTTP $statusCode)' : '';
      final msg = message != null && message!.isNotEmpty ? ': $message' : '';
      return '${prefix}Success$statusInfo$msg';
    } else if (isOffline) {
      return '${prefix}Failed - Device is offline or server unreachable.';
    } else if (statusCode != null) {
      final detail = message != null && message!.isNotEmpty ? ' - $message' : '';
      return '${prefix}Failed (HTTP $statusCode$detail)';
    } else {
      final detail = message != null && message!.isNotEmpty ? ' - $message' : '';
      return '${prefix}Failed$detail';
    }
  }

  @override
  String toString() =>
      'ApiResponse(success: $success, statusCode: $statusCode, message: $message, isOffline: $isOffline)';
}
