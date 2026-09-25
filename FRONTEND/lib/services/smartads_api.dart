import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

class SmartAdsApi {
  SmartAdsApi(this.baseUrl);
  final String baseUrl;
  final http.Client _client = http.Client();
  String? token;

  Future<Map<String, dynamic>> request(String method, String path,
      {Object? body}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          decoded['error'] ?? 'The request could not be completed.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> get(String path) => request('GET', path);
  Future<Map<String, dynamic>> post(String path, {Object? body}) =>
      request('POST', path, body: body);
  Future<Map<String, dynamic>> patch(String path, {Object? body}) =>
      request('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => request('DELETE', path);

  Future<Map<String, dynamic>> uploadVideo(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null)
      throw Exception('Could not read the selected video file.');
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/videos/verify'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files
        .add(http.MultipartFile.fromBytes('video', bytes, filename: file.name));
    final streamed =
        await _client.send(request).timeout(const Duration(minutes: 4));
    final response = await http.Response.fromStream(streamed);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'Video upload failed.');
    }
    return decoded;
  }
}
