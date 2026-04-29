import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final bool isPro;

  AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    required this.isPro,
  });
}

class AuthRepository {
  final _firebaseAuth = FirebaseAuth.instance;

  Future<AuthUser?> checkAuthState(dynamic tursoClient) async {
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) return null;

      final userId = 'firebase_${firebaseUser.uid}';
      final username = firebaseUser.email!.split('@').first;
      bool isPro = false;

      try {
        final resultSet = await tursoClient.query(
          "SELECT is_pro FROM users WHERE id = '${userId.replaceAll("'", "''")}'",
        );
        
        if (resultSet.isEmpty) {
          print('DEBUG AUTH: Usuario no encontrado en Turso. Forzando re-login.');
          return null;
        }

        isPro = resultSet.first['is_pro'] == 1 || resultSet.first['is_pro'] == '1';
      } catch (e) {
        print('DEBUG AUTH: Error consultando Turso = $e');
        return null;
      }

      return AuthUser(
        id: userId,
        name: firebaseUser.displayName ?? username,
        email: firebaseUser.email!,
        photoUrl: firebaseUser.photoURL,
        isPro: isPro,
      );
    } catch (e) {
      print('DEBUG AUTH: Error checking auth state = $e');
      return null;
    }
  }

  Future<AuthUser?> loginWithGoogle(dynamic tursoClient) async {
    try {
      print('DEBUG GOOGLE AUTH: Iniciando flujo...');
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: dotenv.env['GOOGLE_SERVER_CLIENT_ID'],
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(credential);
      final User? firebaseUser = userCredential.user;
      if (firebaseUser == null) return null;

      final userId = 'firebase_${firebaseUser.uid}';
      final username = firebaseUser.email!.split('@').first;

      await tursoClient.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, country, is_pro, reward_tickets)
        VALUES (
          '${userId.replaceAll("'", "''")}',
          '${username.replaceAll("'", "''")}',
          '${(firebaseUser.displayName ?? username).replaceAll("'", "''")}',
          '${firebaseUser.email!.replaceAll("'", "''")}',
          0, 'Bolivia', 0, 0
        )
      ''');

      final resultSet = await tursoClient.query(
        "SELECT is_pro FROM users WHERE id = '${userId.replaceAll("'", "''")}'",
      );
      final isPro = resultSet.isNotEmpty && resultSet.first['is_pro'] == 1;

      return AuthUser(
        id: userId,
        name: firebaseUser.displayName ?? username,
        email: firebaseUser.email!,
        photoUrl: firebaseUser.photoURL,
        isPro: isPro,
      );
    } catch (e) {
      print('DEBUG GOOGLE AUTH ERROR: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
      await user.delete();
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

class UserNotifier extends Notifier<AuthUser?> {
  @override
  AuthUser? build() => null;

  void update(AuthUser? user) => state = user;
}

final currentUserProvider = NotifierProvider<UserNotifier, AuthUser?>(
  () => UserNotifier(),
);
