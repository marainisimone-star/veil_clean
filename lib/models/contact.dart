enum ContactMode {
  plain,
  dualHidden,
}

enum ContactCategory {
  private,
  business,
}

enum CoverStyleOverride {
  auto,
  private,
  business,
}

ContactCategory _categoryFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'business':
      return ContactCategory.business;
    case 'private':
    default:
      return ContactCategory.private;
  }
}

String _categoryToString(ContactCategory c) {
  return (c == ContactCategory.business) ? 'business' : 'private';
}

CoverStyleOverride _coverStyleFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'business':
      return CoverStyleOverride.business;
    case 'private':
      return CoverStyleOverride.private;
    case 'auto':
    default:
      return CoverStyleOverride.auto;
  }
}

String _coverStyleToString(CoverStyleOverride c) {
  switch (c) {
    case CoverStyleOverride.business:
      return 'business';
    case CoverStyleOverride.private:
      return 'private';
    case CoverStyleOverride.auto:
      return 'auto';
  }
}

ContactMode _modeFromString(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'dualhidden':
    case 'dual_hidden':
    case 'dual':
      return ContactMode.dualHidden;
    case 'plain':
    default:
      return ContactMode.plain;
  }
}

String _modeToString(ContactMode m) {
  return (m == ContactMode.dualHidden) ? 'dualHidden' : 'plain';
}

class Contact {
  final String id;
  final String coverName;
  final ContactMode mode;
  final ContactCategory category;
  final CoverStyleOverride coverStyleOverride;

  final String? coverEmoji;
  final String? firstName;
  final String? lastName;
  final String? realName;
  final String? realEmoji;
  final String? phone;
  final String? email;
  final String? address;
  final String? photoB64;
  final bool favorite;

  const Contact({
    required this.id,
    required this.coverName,
    required this.mode,
    required this.category,
    this.coverStyleOverride = CoverStyleOverride.auto,
    this.coverEmoji,
    this.firstName,
    this.lastName,
    this.realName,
    this.realEmoji,
    this.phone,
    this.email,
    this.address,
    this.photoB64,
    this.favorite = false,
  });

  Contact copyWith({
    String? id,
    String? coverName,
    ContactMode? mode,
    ContactCategory? category,
    CoverStyleOverride? coverStyleOverride,
    String? coverEmoji,
    String? firstName,
    String? lastName,
    String? realName,
    String? realEmoji,
    String? phone,
    String? email,
    String? address,
    String? photoB64,
    bool? favorite,
  }) {
    return Contact(
      id: id ?? this.id,
      coverName: coverName ?? this.coverName,
      mode: mode ?? this.mode,
      category: category ?? this.category,
      coverStyleOverride: coverStyleOverride ?? this.coverStyleOverride,
      coverEmoji: coverEmoji ?? this.coverEmoji,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      realName: realName ?? this.realName,
      realEmoji: realEmoji ?? this.realEmoji,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      photoB64: photoB64 ?? this.photoB64,
      favorite: favorite ?? this.favorite,
    );
    }

  Map<String, dynamic> toJson() => {
        'id': id,
        'coverName': coverName,
        'mode': _modeToString(mode),
        'category': _categoryToString(category),
        'coverStyle': _coverStyleToString(coverStyleOverride),
        'coverEmoji': coverEmoji,
        'firstName': firstName,
        'lastName': lastName,
        'realName': realName,
        'realEmoji': realEmoji,
        'phone': phone,
        'email': email,
        'address': address,
        'photoB64': photoB64,
        'favorite': favorite,
      };

  static Contact fromJson(Map<String, dynamic> j) {
    // ✅ Backward-compatible:
    // - se manca "category", default = private
    // - se manca "mode", default = plain
    return Contact(
      id: (j['id'] ?? '').toString(),
      coverName: (j['coverName'] ?? '').toString(),
      mode: _modeFromString(j['mode']?.toString()),
      category: _categoryFromString(j['category']?.toString()),
      coverStyleOverride: _coverStyleFromString(j['coverStyle']?.toString()),
      coverEmoji: (j['coverEmoji']?.toString().trim().isEmpty ?? true)
          ? null
          : j['coverEmoji']?.toString(),
      firstName: (j['firstName']?.toString().trim().isEmpty ?? true)
          ? null
          : j['firstName']?.toString(),
      lastName: (j['lastName']?.toString().trim().isEmpty ?? true)
          ? null
          : j['lastName']?.toString(),
      realName: (j['realName']?.toString().trim().isEmpty ?? true)
          ? null
          : j['realName']?.toString(),
      realEmoji: (j['realEmoji']?.toString().trim().isEmpty ?? true)
          ? null
          : j['realEmoji']?.toString(),
      phone: (j['phone']?.toString().trim().isEmpty ?? true)
          ? null
          : j['phone']?.toString(),
      email: (j['email']?.toString().trim().isEmpty ?? true)
          ? null
          : j['email']?.toString(),
      address: (j['address']?.toString().trim().isEmpty ?? true)
          ? null
          : j['address']?.toString(),
      photoB64: (j['photoB64']?.toString().trim().isEmpty ?? true)
          ? null
          : j['photoB64']?.toString(),
      favorite: (j['favorite'] == true),
    );
  }
}
