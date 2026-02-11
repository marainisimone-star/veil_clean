class AppRoutes {
  AppRoutes._();

  // Entry / security flow
  static const String gate = '/gate';
  static const String lock = '/lock';
  static const String onboarding = '/onboarding';
  static const String auth = '/auth';
  static const String panic = '/panic';

  // Main
  static const String inbox = '/inbox';
  static const String thread = '/thread';
  static const String contacts = '/contacts';
  static const String newConversation = '/new_conversation';

  // Vetrine
  static const String vetrine = '/vetrine';
  static const String vetrinaDetail = '/vetrina_detail';
  static const String vetrinaCreate = '/vetrina_create';

  // Hub
  static const String hub = '/hub';

  // Backup
  static const String backupStatus = '/backup_status';
}
