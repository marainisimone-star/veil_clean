import 'package:veil_clean/models/contact.dart';

class ContactDisplay {
  final String name;
  final String emoji;

  const ContactDisplay({required this.name, required this.emoji});

  static ContactDisplay cover(Contact c) {
    final name = c.coverName.trim().isEmpty ? 'Contact' : c.coverName.trim();
    final emoji = (c.coverEmoji ?? '').trim();
    return ContactDisplay(name: name, emoji: emoji);
  }

  static ContactDisplay real(Contact c) {
    final rn = (c.realName ?? '').trim();
    final re = (c.realEmoji ?? '').trim();

    // If not set, fall back to cover (neutral)
    if (rn.isEmpty && re.isEmpty) return cover(c);

    final name = rn.isEmpty ? (c.coverName.trim().isEmpty ? 'Contact' : c.coverName.trim()) : rn;
    final emoji = re.isEmpty ? (c.coverEmoji ?? '').trim() : re;
    return ContactDisplay(name: name, emoji: emoji);
  }

  /// If not unlocked -> cover.
  /// If unlocked and contact is dualHidden -> real.
  static ContactDisplay forContext(Contact c, {required bool unlocked}) {
    if (!unlocked) return cover(c);

    if (c.mode == ContactMode.dualHidden) {
      return real(c);
    }
    return cover(c);
  }
}
