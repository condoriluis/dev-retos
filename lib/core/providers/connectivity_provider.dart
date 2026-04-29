import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider that streams the current connectivity status.
/// In connectivity_plus v6+, it returns a List<ConnectivityResult>.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// A simpler provider that returns true if there is at least one active connection.
final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  
  return connectivity.when(
    data: (results) {
      // If the list is empty or contains only 'none', we are offline.
      if (results.isEmpty) return false;
      if (results.length == 1 && results.first == ConnectivityResult.none) return false;
      
      // If it contains any other result (wifi, mobile, ethernet, etc), we are online.
      return !results.contains(ConnectivityResult.none);
    },
    loading: () => true, // Assume online while loading to avoid flickering
    error: (_, __) => true,
  );
});
