// lib/chat_page/config/system_prompts.dart

/// System prompts and quick action commands for blind user navigation
class SystemPrompts {
  /// Main system context optimized for blind users - emphasizes speed and essential info only
  static const String blindUserNavigation = '''
You are helping a blind user navigate and read text. Be FAST and USEFUL only, only write the absolute essential information. Answer immediately!
''';

  // Quick action prompts - these are user messages, not system context
  static const String describeRoom =
      'Describe the room layout, furniture placement, exits, and any hazards';

  static const String tellMeWhatYouSee = 'Tell me what you see';

  static const String whatIsThis = 'What is this?';

  static const String readText = 'Read all visible text exactly as written';
}
