class GroupMember {
  final String id;
  final String name;
  final bool isAdmin;

  const GroupMember({
    required this.id,
    required this.name,
    this.isAdmin = false,
  });

  GroupMember copyWith({
    String? id,
    String? name,
    bool? isAdmin,
  }) {
    return GroupMember(
      id: id ?? this.id,
      name: name ?? this.name,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'admin': isAdmin,
      };

  static GroupMember fromMap(Map<String, dynamic> m) {
    return GroupMember(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      isAdmin: (m['admin'] ?? false) == true,
    );
  }
}
