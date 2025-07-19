// download_page/services/huggingface_oauth.dart

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/models.dart';
import 'logger.dart';

class HuggingFaceOAuth {
  static String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  static Future<String> generateAuthUrl() async {
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _generateCodeChallenge(codeVerifier);

    Logger.debug('Generated OAuth code verifier and challenge');

    // Store code verifier for later use
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(codeVerifierKey, codeVerifier);

    final params = {
      'client_id': hfClientId,
      'redirect_uri': hfRedirectUri,
      'response_type': 'code',
      'scope': scope,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    };

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    final authUrl = '$authEndpoint?$query';
    Logger.info('Generated OAuth URL');
    return authUrl;
  }

  static Future<AuthTokenData?> exchangeCodeForToken(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final codeVerifier = prefs.getString(codeVerifierKey);
    if (codeVerifier == null) {
      Logger.error('Code verifier not found');
      return null;
    }

    try {
      Logger.info('Exchanging authorization code for access token');
      final response = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': hfClientId,
          'code': code,
          'redirect_uri': hfRedirectUri,
          'grant_type': 'authorization_code',
          'code_verifier': codeVerifier,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final expiryTime = DateTime.now().add(
          Duration(seconds: data['expires_in'] ?? 3600),
        );

        final tokenData = AuthTokenData(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiryTime: expiryTime,
        );

        // Store token
        await prefs.setString(authTokenKey, json.encode(tokenData.toJson()));
        await prefs.remove(codeVerifierKey);

        Logger.info('Successfully obtained access token');
        return tokenData;
      } else {
        Logger.error(
          'Token exchange failed with status ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      Logger.error('Token exchange error: $e');
    }
    return null;
  }
}
