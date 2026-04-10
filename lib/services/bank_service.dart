import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class BankService {
  static const String _monzoAuthUrl = 'https://auth.monzo.com';
  static const String _defaultTrueLayerAuthUrl = 'https://auth.truelayer.com';
  static const String _defaultFunctionsUrl =
      'https://us-central1-burnrate-app.cloudfunctions.net';
  static const String _defaultMonzoClientId =
      'oauth2client_0000B4e53MWaj3UIGLWqxN';
  static const String _defaultTrueLayerClientId = 'burnrate-039300';
  static const String _defaultTrueLayerProviders = 'uk-ob-all';
  static const String? _defaultTrueLayerProviderId = null;

  final String? monzoClientId;
  final String? trueLayerClientId;
  final String? functionsUrl;
  final String trueLayerAuthUrl;
  final String trueLayerProviders;
  final String? trueLayerProviderId;
  final String? userEmail;

  BankService({
    String? monzoClientId,
    String? trueLayerClientId,
    String? functionsUrl,
    String? trueLayerAuthUrl,
    String? trueLayerProviders,
    String? trueLayerProviderId,
    this.userEmail,
  }) : monzoClientId = monzoClientId ?? _defaultMonzoClientId,
       trueLayerClientId = trueLayerClientId ?? _defaultTrueLayerClientId,
       functionsUrl = functionsUrl ?? _defaultFunctionsUrl,
       trueLayerAuthUrl = trueLayerAuthUrl ?? _defaultTrueLayerAuthUrl,
       trueLayerProviders = trueLayerProviders ?? _defaultTrueLayerProviders,
       trueLayerProviderId = trueLayerProviderId ?? _defaultTrueLayerProviderId;

  bool get isMonzoConfigured =>
      monzoClientId != null && monzoClientId!.isNotEmpty;
  bool get isTrueLayerConfigured =>
      trueLayerClientId != null && trueLayerClientId!.isNotEmpty;

  Future<Map<String, bool>> fetchBankStatus(User user) async {
    final token = await user.getIdToken();
    final response = await http.get(
      Uri.parse('$functionsUrl/bankStatus'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch bank status');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'monzo': data['monzo'] == true,
      'truelayer': data['truelayer'] == true,
    };
  }

  Future<void> syncProvider(User user, String provider) async {
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$functionsUrl/manualSync'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'provider': provider}),
    );

    if (response.statusCode != 200) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final message = (data['error'] as String?)?.trim();
        if (message != null && message.isNotEmpty) {
          throw Exception(message);
        }
      } catch (_) {
        // Fall back to a generic error if response parsing fails.
      }
      throw Exception('Failed to sync $provider');
    }
  }

  Future<void> connectMonzo(String uid) async {
    if (!isMonzoConfigured) return;
    final params = {
      'client_id': monzoClientId!,
      'redirect_uri': '$functionsUrl/monzoCallback',
      'response_type': 'code',
      'state': uid,
    };
    final uri = Uri.parse('$_monzoAuthUrl/').replace(queryParameters: params);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> connectLloyds(String uid) async {
    if (!isTrueLayerConfigured) return;
    final params = <String, String>{
      'response_type': 'code',
      'client_id': trueLayerClientId!,
      'scope': 'info accounts balance transactions offline_access',
      'redirect_uri': '$functionsUrl/truelayerCallback',
      'providers': trueLayerProviders,
      'state': uid,
    };

    if (trueLayerProviderId != null && trueLayerProviderId!.isNotEmpty) {
      params['provider_id'] = trueLayerProviderId!;
    }

    if (userEmail != null && userEmail!.isNotEmpty) {
      params['user_email'] = userEmail!;
    }

    final uri = Uri.parse(
      '$trueLayerAuthUrl/',
    ).replace(queryParameters: params);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
