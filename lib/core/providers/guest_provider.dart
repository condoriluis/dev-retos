import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Provider to track if the user has entered as a guest ('Jugar' mode)
final guestModeProvider = StateProvider<bool>((ref) => false);

/// Provider to retrieve or generate a unique persistent ID for this guest device
final guestIdProvider = Provider<String>((ref) {
  // Note: This is a synchronous provider for ease of use in other providers.
  // It assumes SharedPreferences are pre-warmed or handles the default case.
  final prefs = ref.watch(_guestPrefsProvider).value;
  if (prefs == null) return 'temporary_guest';

  String? storedId = prefs.getString('persistent_guest_id');
  if (storedId == null) {
    storedId = 'guest_${const Uuid().v4()}';
    prefs.setString('persistent_guest_id', storedId);
  }
  return storedId;
});

// Internal provider to access SharedPreferences
final _guestPrefsProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});
