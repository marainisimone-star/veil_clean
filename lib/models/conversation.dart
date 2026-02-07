import 'group_member.dart';

class Conversation {
  final String id;

  /// Cover title shown in inbox and thread title (innocuous)
  final String title;

  /// Optional link to a contact (for hidden identity panel)
  final String? contactId;

  final String lastMessage;
  final DateTime lastUpdated;
  final int unreadCount;

  /// Cover tone for innocuous text generation (Business / Private)
  final CoverStyle coverStyle;

  /// Optional: auto-delete messages after N minutes (null = off)
  final int? messageTtlMinutes;

  /// Whether this conversation is hidden (decoy inbox)
  final bool isHidden;

  /// Group chat flag
  final bool isGroup;

  /// Group members (local-only)
  final List<GroupMember> groupMembers;

  const Conversation({
    required this.id,
    required this.title,
    required this.lastMessage,
    required this.lastUpdated,
    required this.unreadCount,
    this.contactId,
    this.coverStyle = CoverStyle.private,
    this.messageTtlMinutes,
    this.isHidden = false,
    this.isGroup = false,
    this.groupMembers = const [],
  });

  Conversation copyWith({
    String? title,
    String? contactId,
    String? lastMessage,
    DateTime? lastUpdated,
    int? unreadCount,
    CoverStyle? coverStyle,
    int? messageTtlMinutes,
    bool? isHidden,
    bool? isGroup,
    List<GroupMember>? groupMembers,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      contactId: contactId ?? this.contactId,
      lastMessage: lastMessage ?? this.lastMessage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      unreadCount: unreadCount ?? this.unreadCount,
      coverStyle: coverStyle ?? this.coverStyle,
      messageTtlMinutes: messageTtlMinutes ?? this.messageTtlMinutes,
      isHidden: isHidden ?? this.isHidden,
      isGroup: isGroup ?? this.isGroup,
      groupMembers: groupMembers ?? this.groupMembers,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'contactId': contactId,
      'last': lastMessage,
      'updated': lastUpdated.toIso8601String(),
      'unread': unreadCount,
      'coverStyle': coverStyle.name,
      'ttlMinutes': messageTtlMinutes,
      'hidden': isHidden,
      'isGroup': isGroup,
      'members': groupMembers.map((m) => m.toMap()).toList(growable: false),
    };
  }

  static Conversation fromMap(Map<String, dynamic> m) {
    final rawStyle = (m['coverStyle'] ?? 'private') as String;
    final style = CoverStyle.values.firstWhere(
      (e) => e.name == rawStyle,
      orElse: () => CoverStyle.private,
    );

    int? ttl;
    final rawTtl = m['ttlMinutes'];
    if (rawTtl is int) ttl = rawTtl;
    if (rawTtl is String) ttl = int.tryParse(rawTtl);

    final rawHidden = m['hidden'];
    final isHidden = (rawHidden is bool) ? rawHidden : false;

    final rawIsGroup = m['isGroup'];
    final isGroup = (rawIsGroup is bool) ? rawIsGroup : false;

    final membersRaw = m['members'];
    final members = <GroupMember>[];
    if (membersRaw is List) {
      for (final item in membersRaw) {
        if (item is Map) {
          members.add(GroupMember.fromMap(item.cast<String, dynamic>()));
        }
      }
    }

    return Conversation(
      id: (m['id'] ?? '') as String,
      title: (m['title'] ?? '') as String,
      contactId: (m['contactId'] as String?),
      lastMessage: (m['last'] ?? '') as String,
      lastUpdated: DateTime.tryParse((m['updated'] ?? '') as String) ?? DateTime.now(),
      unreadCount: (m['unread'] ?? 0) as int,
      coverStyle: style,
      messageTtlMinutes: ttl,
      isHidden: isHidden,
      isGroup: isGroup,
      groupMembers: members,
    );
  }
}

enum CoverStyle { private, business }
