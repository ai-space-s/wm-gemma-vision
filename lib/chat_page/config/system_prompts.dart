// lib/chat_page/config/system_prompts.dart

class SystemPrompts {
  static const String blindUserNavigation = '''
You are helping a blind user navigate and read text. Be FAST and USEFUL only, only write the absolute essential information. Answer immediately!
''';

  // Quick action prompts - these are added to the user message, not system context
  static const String describeRoom =
      'Describe the room layout, furniture placement, exits, and any hazards';

  static const String tellMeWhatYouSee =
      'Tell me what you see focusing on obstacles, people, hazards, and clear paths';

  static const String findExit =
      'Find an exit - locate doors, pathways out, give directions and distance';

  static const String readText = 'Read all visible text exactly as written';
}
