import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:libsql_dart/libsql_dart.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'turso_client.g.dart';

class TursoConfig {
  static String get url => dotenv.env['TURSO_URL'] ?? '';
  static String get authToken => dotenv.env['TURSO_AUTH_TOKEN'] ?? '';
}

@Riverpod(keepAlive: true)
LibsqlClient tursoClient(Ref ref) {
  final client = LibsqlClient.remote(
    TursoConfig.url,
    authToken: TursoConfig.authToken,
  );

  return client;
}
