import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool connectionFailure;
  const ApiException(this.message,
      {this.statusCode, this.connectionFailure = false});

  @override
  String toString() => message;
}

class BackendClient {
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://krishi-backend-ox3u.onrender.com',
  );

  final http.Client _client;
  final Future<String?> Function(bool forceRefresh) tokenProvider;
  final String baseUrl;
  final Duration timeout;

  BackendClient({
    required this.tokenProvider,
    http.Client? client,
    this.baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client();

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _request('POST', path, body);

  Future<Map<String, dynamic>> get(String path) => _request('GET', path);

  Future<Map<String, dynamic>> _request(String method, String path,
      [Map<String, dynamic>? body]) async {
    try {
      final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await tokenProvider(attempt > 0)
            .timeout(const Duration(seconds: 15));
        if (token == null || token.isEmpty) {
          throw const ApiException('Please sign in before continuing.');
        }
        final uri = Uri.parse('$base$path');
        final headers = {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        };
        final response = await (method == 'GET'
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(timeout);
        if (response.statusCode == 401 && attempt == 0) continue;
        Map<String, dynamic> data;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) throw const FormatException();
          data = decoded;
        } on FormatException {
          throw const ApiException(
              'The server returned an unexpected response. Please try again.');
        }
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return data;
        }
        if (response.statusCode == 401) {
          throw const ApiException(
              'Your session expired. Please sign in again.',
              statusCode: 401);
        }
        final detail = data['detail'];
        String message;
        if (detail is String) {
          message = detail;
        } else if (detail is List) {
          message = detail
              .whereType<Map>()
              .map((error) => error['msg']?.toString() ?? 'Check your input.')
              .join('\n');
        } else {
          message = 'The request failed. Please try again.';
        }
        throw ApiException(message, statusCode: response.statusCode);
      }
      throw const ApiException('Please sign in again.');
    } on TimeoutException {
      // Do not retry a timed-out mutation: it may already have succeeded.
      throw const ApiException(
          'The server took too long. Check your surveys before trying again.',
          connectionFailure: true);
    } on http.ClientException {
      throw const ApiException(
          'Could not reach the server. Check your connection and try again.',
          connectionFailure: true);
    }
  }

  void close() => _client.close();
}
