import 'package:libsql_dart/libsql_dart.dart';
import 'package:dev_retos/core/database/turso_client.dart';

void main() async {
  print('Iniciando migración manual de base de datos a Turso...');
  final client = LibsqlClient.remote(
    TursoConfig.url,
    authToken: TursoConfig.authToken,
  );

  await client.connect();
  print('✅ Conexión establecida a Turso: \${TursoConfig.url}');

  print('1. Creando tabla: users...');
  await client.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      email TEXT UNIQUE NOT NULL,
      xp INTEGER DEFAULT 0,
      country TEXT DEFAULT 'Bolivia',
      is_pro INTEGER DEFAULT 0,
      current_streak INTEGER DEFAULT 0,
      highest_streak INTEGER DEFAULT 0,
      best_time INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  print('2. Creando tabla: challenges...');
  await client.execute('''
    CREATE TABLE IF NOT EXISTS challenges (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      question TEXT NOT NULL,
      code_snippet TEXT,
      correct_answer TEXT NOT NULL,
      technology TEXT NOT NULL,
      level TEXT NOT NULL,
      is_premium INTEGER DEFAULT 0,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  print('3. Creando tabla: daily_challenges...');
  await client.execute('''
    CREATE TABLE IF NOT EXISTS daily_challenges (
      display_date DATE PRIMARY KEY,
      challenge_id TEXT NOT NULL,
      FOREIGN KEY(challenge_id) REFERENCES challenges(id)
    );
  ''');

  print('4. Creando tabla: user_sessions...');
  await client.execute('''
    CREATE TABLE IF NOT EXISTS user_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      challenge_id TEXT NOT NULL,
      time_taken_seconds INTEGER,
      is_success INTEGER NOT NULL,
      attempts_used INTEGER DEFAULT 1,
      completed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY(user_id) REFERENCES users(id),
      FOREIGN KEY(challenge_id) REFERENCES challenges(id)
    );
  ''');

  print('✅ Tablas creadas con éxito.');
  print('5. Insertando datos de prueba (Mock Data)...');

  try {
    // User mock
    await client.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, country, is_pro) 
        VALUES ('u1', 'LuisDev', 'Luis', 'luis@test.com', 6013, 'Bolivia', 1);
     ''');

    // Challenge mock
    await client.execute('''
        INSERT OR IGNORE INTO challenges (id, title, question, code_snippet, correct_answer, technology, level, is_premium)
        VALUES (
          'c1', 
          'Lógica Frontend: Tipos Cero', 
          '¿Cuál es el output del siguiente código en JavaScript?', 
          'console.log(typeof null);\nconsole.log(typeof NaN);', 
          'object number',
          'JavaScript',
          'BEGINNER',
          0
        );
     ''');

    // Daily mock (for today: 2026-04-15)
    await client.execute('''
        INSERT OR IGNORE INTO daily_challenges (display_date, challenge_id)
        VALUES ('2026-04-15', 'c1');
     ''');

    print('✅ Datos de prueba insertados o actualizados correctamente.');
    print('🚀 Migración terminada exitosamente.');
  } catch (e) {
    print('❌ Error insertando datos: \$e');
  }
}
