import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'offline_coach_config.dart';

/// Online advisor service (Claude via Firebase Functions).
///
/// This keeps the Anthropic API key on the server and only sends
/// user-approved context when the user opts in.
class OnlineAiService {
  OnlineAiService._();
  static final OnlineAiService instance = OnlineAiService._();

  Future<String> sendMessage({
    required String userMessage,
    required List<Map<String, String>> history,
    Map<String, dynamic>? financialContext,
    required bool deepInsights,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in to use online AI advisor.');
    }

    final idToken = await user.getIdToken();
    final endpoint = _buildEndpoint();
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'message': userMessage,
        'history': history,
        'financialContext': financialContext ?? const <String, dynamic>{},
        'deepInsights': deepInsights,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Online advisor failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Online advisor returned an invalid response.');
    }
    final text = (decoded['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      throw StateError('Online advisor returned an empty response.');
    }
    return text;
  }

  String _buildEndpoint() {
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return 'https://${OfflineCoachConfig.onlineFunctionRegion}-$projectId.cloudfunctions.net/${OfflineCoachConfig.onlineFunctionName}';
  }
}
