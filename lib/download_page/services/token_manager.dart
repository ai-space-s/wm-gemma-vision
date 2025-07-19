// download_page/services/token_manager.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import '../models/models.dart';
import '../models/enums.dart';
import 'logger.dart';

class TokenManager {
  static Future<TokenStatus> getTokenStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenString = prefs.getString(authTokenKey);

    if (tokenString == null) {
      Logger.debug('No stored token found');
      return TokenStatus.notStored;
    }

    try {
      final tokenData = AuthTokenData.fromJson(json.decode(tokenString));
      final status = tokenData.isExpired
          ? TokenStatus.expired
          : TokenStatus.valid;
      Logger.debug('Token status: $status');
      return status;
    } catch (e) {
      Logger.error('Error reading stored token: $e');
      return TokenStatus.notStored;
    }
  }

  static Future<AuthTokenData?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenString = prefs.getString(authTokenKey);

    if (tokenString == null) return null;

    try {
      return AuthTokenData.fromJson(json.decode(tokenString));
    } catch (e) {
      Logger.error('Error parsing stored token: $e');
      return null;
    }
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(authTokenKey);
    Logger.info('Cleared stored token');
  }
}
