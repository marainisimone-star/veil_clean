class SecureGate {
  SecureGate._();

  // Session-level gate (owner authenticated in this run)
  static bool _sessionUnlocked = false;

  // Per-conversation gates
  static final Set<String> _unlockedConversations = <String>{};

  // Global panic blocks everything
  static bool _panicActive = false;

  // During biometric/system auth we MUST NOT auto-lock on lifecycle transitions
  static bool _authInProgress = false;

  // Optional reason for debugging / neutral UX
  static String _lastBlockReason = 'Locked: operations blocked';

  // ---------------- Queries ----------------

  static bool get isPanicActive => _panicActive;

  static bool get isSessionUnlocked => _sessionUnlocked && !_panicActive;

  static bool get isAuthInProgress => _authInProgress;

  static bool isConversationUnlocked(String conversationId) {
    if (_panicActive) return false;
    if (!_sessionUnlocked) return false;
    return _unlockedConversations.contains(conversationId);
  }

  static String get lastBlockReason => _lastBlockReason;

  // ---------------- Mutations ----------------

  /// Call before opening OS biometric prompt (Hello/FaceID/etc.)
  static void beginOwnerAuth() {
    _authInProgress = true;
  }

  /// Call after OS biometric prompt closes
  static void endOwnerAuth() {
    _authInProgress = false;
  }

  /// Unlocks the session for the current app run (after owner auth).
  static void unlockSession() {
    _sessionUnlocked = true;
    _lastBlockReason = 'OK';
  }

  /// Locks the session and clears all per-conversation unlocks.
  static void lockSession({String reason = 'Locked: operations blocked'}) {
    _sessionUnlocked = false;
    _unlockedConversations.clear();
    _lastBlockReason = reason;
  }

  /// Unlock a specific conversation (requires session unlocked, panic inactive).
  static void unlockConversation(String conversationId) {
    if (_panicActive) {
      _lastBlockReason = 'Locked: operations blocked';
      return;
    }
    if (!_sessionUnlocked) {
      _lastBlockReason = 'Locked: operations blocked';
      return;
    }
    _unlockedConversations.add(conversationId);
    _lastBlockReason = 'OK';
  }

  static void lockConversation(
    String conversationId, {
    String reason = 'Locked: operations blocked',
  }) {
    _unlockedConversations.remove(conversationId);
    _lastBlockReason = reason;
  }

  /// Global panic: blocks all operations and clears all unlocks.
  static void activateGlobalPanic({String reason = 'Locked: operations blocked'}) {
    _panicActive = true;
    _sessionUnlocked = false;
    _unlockedConversations.clear();
    _lastBlockReason = reason;
  }

  /// Clears panic (owner flow should decide when it is allowed).
  static void clearGlobalPanic() {
    _panicActive = false;
    _lastBlockReason = 'Locked: operations blocked';
  }

  // ---------------- Enforcement ----------------

  /// Throws if session/conversation is not in a state to perform crypto ops.
  static void ensureUnlockedOrThrow({String? conversationId}) {
    if (_panicActive) {
      throw StateError(_lastBlockReason.isEmpty ? 'Locked: operations blocked' : _lastBlockReason);
    }

    if (!_sessionUnlocked) {
      throw StateError(_lastBlockReason.isEmpty ? 'Locked: operations blocked' : _lastBlockReason);
    }

    if (conversationId != null && conversationId.isNotEmpty) {
      if (!_unlockedConversations.contains(conversationId)) {
        throw StateError(_lastBlockReason.isEmpty ? 'Locked: operations blocked' : _lastBlockReason);
      }
    }
  }
}
