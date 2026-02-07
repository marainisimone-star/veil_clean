import 'contact_policy_store.dart';
import 'onboarding_store.dart';
import 'owner_auth_service.dart';

class ResetSetupService {
  static final ResetSetupService _instance = ResetSetupService._internal();
  factory ResetSetupService() => _instance;
  ResetSetupService._internal();

  /// Reset “setup”:
  /// - onboarding completed = false
  /// - hidden keys = vuoto
  /// - seen snapshot = vuoto
  /// - policy hidden = vuoto
  ///
  /// Nota: NON cancelliamo i messaggi/conversazioni (quello è uno step separato).
  /// Se vuoi anche quello, lo facciamo dopo come opzione “factory reset”.
  Future<void> resetOnboardingAndPolicies() async {
    await OnboardingStore().resetAll();
    await ContactPolicyStore().reset();
  }

  /// Reset completo anche PIN/opzione.
  /// (Non lo usiamo di default: lo teniamo separato per non farti perdere il PIN
  /// se vuoi solo rifare la scelta contatti.)
  Future<void> resetAllIncludingPins() async {
    await resetOnboardingAndPolicies();
    await OwnerAuthService().clearAll();
  }
}
