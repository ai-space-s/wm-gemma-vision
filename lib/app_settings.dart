// lib/app_settings.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_page/config/system_prompts.dart';

enum AppFontSize { normal, large }

class AppSettings extends ChangeNotifier {
  static final AppSettings instance = AppSettings._internal();
  AppSettings._internal();

  static const _keyHapticsEnabled = 'hapticsEnabled';
  static const _keyEarconsEnabled = 'earconsEnabled';
  static const _keyHighContrastEnabled = 'highContrastEnabled';
  static const _keyFontSize = 'fontSize';
  static const _keyEnableFunctionCalling = 'enableFunctionCalling';
  static const _keyStreamingResponsesEnabled = 'streamingResponsesEnabled';

  // 프롬프트 저장을 위한 키
  static const _keySystemContext = 'systemContext';
  static const _keyPromptRoom = 'promptDescribeRoom';
  static const _keyPromptSee = 'promptWhatYouSee';
  static const _keyPromptWhat = 'promptWhatIsThis';
  static const _keyPromptRead = 'promptReadText';

  bool hapticsEnabled = true;
  bool earconsEnabled = true;
  bool highContrastEnabled = false;
  bool enableFunctionCalling = true;
  bool streamingResponsesEnabled = true;
  AppFontSize fontSize = AppFontSize.normal;

  // 프롬프트 변수 (기본값은 SystemPrompts 상수)
  String systemContext = SystemPrompts.defaultSystemContext;
  String promptDescribeRoom = SystemPrompts.describeRoom;
  String promptWhatYouSee = SystemPrompts.tellMeWhatYouSee;
  String promptWhatIsThis = SystemPrompts.whatIsThis;
  String promptReadText = SystemPrompts.readText;

  double get textScaleFactor => fontSize == AppFontSize.large ? 1.6 : 1.0;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    hapticsEnabled = prefs.getBool(_keyHapticsEnabled) ?? true;
    earconsEnabled = prefs.getBool(_keyEarconsEnabled) ?? true;
    highContrastEnabled = prefs.getBool(_keyHighContrastEnabled) ?? false;
    enableFunctionCalling = prefs.getBool(_keyEnableFunctionCalling) ?? true;
    streamingResponsesEnabled =
        prefs.getBool(_keyStreamingResponsesEnabled) ?? true;
    final fontSizeIndex =
        prefs.getInt(_keyFontSize) ?? AppFontSize.normal.index;
    fontSize = AppFontSize
        .values[fontSizeIndex.clamp(0, AppFontSize.values.length - 1)];

    // 저장된 프롬프트 로드 (없으면 기본값 사용)
    systemContext =
        prefs.getString(_keySystemContext) ??
        SystemPrompts.defaultSystemContext;
    promptDescribeRoom =
        prefs.getString(_keyPromptRoom) ?? SystemPrompts.describeRoom;
    promptWhatYouSee =
        prefs.getString(_keyPromptSee) ?? SystemPrompts.tellMeWhatYouSee;
    promptWhatIsThis =
        prefs.getString(_keyPromptWhat) ?? SystemPrompts.whatIsThis;
    promptReadText = prefs.getString(_keyPromptRead) ?? SystemPrompts.readText;

    notifyListeners();
  }

  Future<void> update({
    required bool hapticsEnabled,
    required bool earconsEnabled,
    required bool highContrastEnabled,
    required bool enableFunctionCalling,
    required bool streamingResponsesEnabled,
    required AppFontSize fontSize,
  }) async {
    this.hapticsEnabled = hapticsEnabled;
    this.earconsEnabled = earconsEnabled;
    this.highContrastEnabled = highContrastEnabled;
    this.enableFunctionCalling = enableFunctionCalling;
    this.streamingResponsesEnabled = streamingResponsesEnabled;
    this.fontSize = fontSize;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHapticsEnabled, hapticsEnabled);
    await prefs.setBool(_keyEarconsEnabled, earconsEnabled);
    await prefs.setBool(_keyHighContrastEnabled, highContrastEnabled);
    await prefs.setBool(_keyEnableFunctionCalling, enableFunctionCalling);
    await prefs.setBool(
      _keyStreamingResponsesEnabled,
      streamingResponsesEnabled,
    );
    await prefs.setInt(_keyFontSize, fontSize.index);

    notifyListeners();
  }

  // 프롬프트만 따로 업데이트하는 메소드
  Future<void> updatePrompts({
    required String systemContext,
    required String describeRoom,
    required String whatYouSee,
    required String whatIsThis,
    required String readText,
  }) async {
    this.systemContext = systemContext;
    promptDescribeRoom = describeRoom;
    promptWhatYouSee = whatYouSee;
    promptWhatIsThis = whatIsThis;
    promptReadText = readText;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySystemContext, systemContext);
    await prefs.setString(_keyPromptRoom, describeRoom);
    await prefs.setString(_keyPromptSee, whatYouSee);
    await prefs.setString(_keyPromptWhat, whatIsThis);
    await prefs.setString(_keyPromptRead, readText);

    notifyListeners();
  }

  void maybeHapticTap() {
    if (!hapticsEnabled) return;
    HapticFeedback.lightImpact();
  }
}
