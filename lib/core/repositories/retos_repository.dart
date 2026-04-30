import 'package:dev_retos/core/providers/guest_provider.dart';
import 'package:libsql_dart/libsql_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/turso_client.dart';
import '../services/ai_challenge_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'auth_repository.dart';

class RetosRepository {
  final LibsqlClient _client;

  RetosRepository(this._client);

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is BigInt) return value.toInt();
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Elimina todos los datos de un usuario en Turso (sesiones y perfil).
  Future<void> deleteUserAccount(String userId) async {
    print('DEBUG DB: Eliminando datos del usuario $userId...');
    await _client.execute(
      "DELETE FROM user_sessions WHERE user_id = '$userId'",
    );
    await _client.execute("DELETE FROM users WHERE id = '$userId'");
  }

  /// Ejecuta migraciones para crear tablas y mock data si no existen.
  Future<void> initDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDbInitialized = prefs.getBool('db_initialized') ?? false;

      // Activa esta línea solo UNA vez para limpiar todo antes del lanzamiento con F5
      // await _clearAllData();

      // 1. Habilitar FK
      await _client.execute('PRAGMA foreign_keys = ON;');

      if (!isDbInitialized) {
        print('DEBUG DB: Creando tabla users...');
        await _client.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id TEXT PRIMARY KEY,
          username TEXT UNIQUE NOT NULL,
          name TEXT NOT NULL,
          email TEXT UNIQUE NOT NULL,
          xp INTEGER DEFAULT 0,
          country TEXT DEFAULT 'Bolivia',
          is_pro INTEGER DEFAULT 0,
          reward_tickets INTEGER DEFAULT 0,
          current_streak INTEGER DEFAULT 0,
          best_time INTEGER,
          last_username_update DATETIME
        );
      ''');
        print('DEBUG DB: Tabla users verificada/creada.');

        print('DEBUG DB: Creando tabla challenges...');
        await _client.execute('''
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
        print('DEBUG DB: Tabla challenges verificada/creada.');

        print('DEBUG DB: Creando tabla daily_challenges...');
        await _client.execute('''
        CREATE TABLE IF NOT EXISTS daily_challenges (
          display_date DATE PRIMARY KEY,
          challenge_id TEXT NOT NULL,
          FOREIGN KEY(challenge_id) REFERENCES challenges(id)
        );
      ''');
        print('DEBUG DB: Tabla daily_challenges verificada/creada.');

        print('DEBUG DB: Creando tabla user_sessions...');
        await _client.execute('''
        CREATE TABLE IF NOT EXISTS user_sessions (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          challenge_id TEXT NOT NULL,
          time_taken_seconds INTEGER,
          is_success INTEGER NOT NULL,
          attempts INTEGER DEFAULT 1,
          completed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(user_id) REFERENCES users(id),
          FOREIGN KEY(challenge_id) REFERENCES challenges(id),
          UNIQUE(user_id, challenge_id)
        );
      ''');
        print('DEBUG DB: Tabla user_sessions verificada/creada.');

        // Agregado de migración sin ruptura: Columna xp_earned
        try {
          await _client.execute(
            'ALTER TABLE user_sessions ADD COLUMN xp_earned INTEGER DEFAULT 0',
          );
          print(
            'DEBUG DB: Columna xp_earned añadida a user_sessions (Migración O.K.)',
          );
        } catch (_) {
          // Si ya existe u ocurre error, ignoramos silenciosamente
        }

        try {
          await _client.execute(
            'ALTER TABLE users ADD COLUMN last_played_date DATE',
          );
        } catch (_) {}
        try {
          await _client.execute(
            'ALTER TABLE users ADD COLUMN last_shield_used DATE',
          );
        } catch (_) {}
        try {
          await _client.execute(
            'ALTER TABLE users ADD COLUMN notified_shield INTEGER DEFAULT 1',
          );
        } catch (_) {}

        await prefs.setBool('db_initialized', true);
        print('DEBUG DB: Tablas base de datos inicializadas.');
      }

      // Migraciones de esquema post-inicialización
      try {
        await _client.execute(
          'ALTER TABLE user_sessions ADD COLUMN completion_date DATE',
        );
        print('DEBUG DB: Columna completion_date añadida a user_sessions');
        // Poblamos datos antiguos usando UTC como fallback (mejor que NULL)
        await _client.execute(
          "UPDATE user_sessions SET completion_date = DATE(completed_at, 'localtime') WHERE completion_date IS NULL",
        );
      } catch (_) {}

      try {
        await _client.execute(
          'ALTER TABLE challenges ADD COLUMN is_ai INTEGER DEFAULT 0',
        );
      } catch (_) {}

      // Migración de Índice para Analíticas PRO
      try {
        await _client.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_sessions_stats ON user_sessions (user_id, is_success, completion_date)',
        );
        print('DEBUG DB: Índice idx_user_sessions_stats verificado/creado');
      } catch (_) {}
      try {
        await _client.execute(
          'ALTER TABLE challenges ADD COLUMN creator_id TEXT',
        );
      } catch (_) {}

      // Re-verificación de retos (por si se borró la DB remota pero no las prefs locales)
      await _seedInitialChallenges();

      // 9. Seleccionar 3 retos diarios para los últimos 7 días si no existen
      for (int i = 0; i < 7; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final dateStr = date.toIso8601String().substring(0, 10);

        final checkDaily = await _client.query(
          "SELECT * FROM daily_challenges WHERE display_date = '$dateStr'",
        );

        if (checkDaily.isEmpty) {
          // Intentar obtener retos que el usuario ya completó este día para "reparar" la racha
          final completedOnDay = await _client.query('''
            SELECT challenge_id FROM user_sessions 
            WHERE completion_date = '$dateStr' AND is_success = 1
            LIMIT 3
          ''');

          final List<String> existingCids = checkDaily
              .map((d) => d['challenge_id'].toString())
              .toList();
          final List<String> toAdd = [];

          // Priorizar los que ya hizo el usuario
          for (var row in completedOnDay) {
            final cid = row['challenge_id'].toString();
            if (!existingCids.contains(cid)) toAdd.add(cid);
          }

          // Rellenar con aleatorios si faltan hasta llegar a 3
          if (toAdd.length + existingCids.length < 1) {
            final needed = 1 - (toAdd.length + existingCids.length);
            final randomChallenges = await _client.query(
              "SELECT id FROM challenges WHERE id NOT IN (${[...existingCids, ...toAdd].map((e) => "'$e'").join(',')}) ORDER BY RANDOM() LIMIT $needed",
            );
            for (var row in randomChallenges) {
              toAdd.add(row['id'].toString());
            }
          }

          for (var cid in toAdd) {
            await _client.execute(
              "INSERT OR REPLACE INTO daily_challenges (display_date, challenge_id) VALUES ('$dateStr', '$cid')",
            );
          }
        }
      }

      print('✅ Base de datos inicializada con retos profesionales dinámicos.');
    } catch (e) {
      print('❌ Error crítico en initDatabase: $e');
    }
  }

  /// Trae los 3 retos diarios basados en la fecha actual, incluyendo estado de éxito para el usuario
  Future<List<Map<String, dynamic>>> getDailyChallenges(String userId) async {
    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final start = DateTime.now();

      final queryJob = _client.query('''
        SELECT c.*, 
          COALESCE(us.is_success, 0) as is_completed,
          COALESCE(us.time_taken_seconds, 0) as time_taken,
          COALESCE(us.attempts, 0) as user_attempts
        FROM challenges c
        INNER JOIN daily_challenges d ON c.id = d.challenge_id
        LEFT JOIN user_sessions us ON us.challenge_id = c.id 
          AND us.user_id = '$userId' 
          AND us.completion_date = '$date'
        WHERE d.display_date = '$date'
        ORDER BY c.id ASC
      ''');

      final resultSet = await queryJob;
      final elapsed = DateTime.now().difference(start);
      if (elapsed < const Duration(milliseconds: 400)) {
        await Future.delayed(const Duration(milliseconds: 400) - elapsed);
      }

      return resultSet
          .map(
            (row) => {
              'id': row['id']?.toString() ?? '',
              'title': row['title']?.toString() ?? 'Reto',
              'question': row['question']?.toString() ?? '',
              'code_snippet': row['code_snippet']?.toString() ?? '',
              'technology': row['technology']?.toString() ?? '',
              'level': row['level']?.toString() ?? '',
              'is_completed':
                  row['is_completed'] == 1 || row['is_completed'] == '1' || row['is_completed'] == -1 || row['is_completed'] == '-1',
              'is_abandoned': row['is_completed'] == -1 || row['is_completed'] == '-1',
              'time_taken': _toInt(row['time_taken']),
              'attempts': _toInt(row['user_attempts']),
            },
          )
          .toList();
    } catch (e) {
      print('Exception getDaily: $e');
      return [];
    }
  }

  /// Trae el número de intentos fallidos del usuario para un reto hoy
  Future<int> getChallengeAttempts(String challengeId, String userId) async {
    try {
      final resultSet = await _client.query('''
        SELECT attempts FROM user_sessions 
        WHERE user_id = '$userId' AND challenge_id = '$challengeId'
        AND completion_date = '${DateTime.now().toIso8601String().substring(0, 10)}'
      ''');
      if (resultSet.isNotEmpty) {
        final val = resultSet.first['attempts'];
        if (val is BigInt) return val.toInt();
        return (val as int? ?? 0);
      }
      return 0;
    } catch (e) {
      print('Error getChallengeAttempts: $e');
      return 0;
    }
  }

  /// Trae el perfil del usuario desde Turso
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final start = DateTime.now();
      final queryJob = _client.query('''
        SELECT u.*,
          COALESCE((SELECT COUNT(*) FROM user_sessions us WHERE us.user_id = u.id AND EXISTS (SELECT 1 FROM daily_challenges dc WHERE dc.challenge_id = us.challenge_id AND dc.display_date = us.completion_date)), 0) as total_played,
          COALESCE((SELECT COUNT(*) FROM user_sessions us WHERE us.user_id = u.id AND EXISTS (SELECT 1 FROM daily_challenges dc WHERE dc.challenge_id = us.challenge_id AND dc.display_date = us.completion_date) AND us.is_success = 1), 0) as total_won,
          COALESCE((SELECT MIN(us.time_taken_seconds) FROM user_sessions us WHERE us.user_id = u.id AND EXISTS (SELECT 1 FROM daily_challenges dc WHERE dc.challenge_id = us.challenge_id AND dc.display_date = us.completion_date) AND us.is_success = 1), 0) as best_time
        FROM users u 
        WHERE u.id = '$userId'
      ''');

      final resultSet = await queryJob;

      final elapsed = DateTime.now().difference(start);
      // Reducido a 400ms para mayor fluidez
      if (elapsed < const Duration(milliseconds: 400)) {
        await Future.delayed(const Duration(milliseconds: 400) - elapsed);
      }

      if (resultSet.isNotEmpty) {
        final row = Map<String, dynamic>.from(resultSet.first);
        final bool isPro =
            (row['is_pro'] == 1 ||
            row['is_pro'] == true ||
            row['is_pro']?.toString() == '1');
        int currentStreak = row['current_streak'] as int? ?? 0;
        int notifiedShield = row['notified_shield'] as int? ?? 1;

        final lastPlayedStr = row['last_played_date']?.toString();
        if (lastPlayedStr != null && currentStreak > 0) {
          final now = DateTime.now();
          final todayDate = DateTime(now.year, now.month, now.day);
          final lastPlayed = DateTime.tryParse(lastPlayedStr);

          if (lastPlayed != null) {
            final lastDate = DateTime(
              lastPlayed.year,
              lastPlayed.month,
              lastPlayed.day,
            );
            final difference = todayDate.difference(lastDate).inDays;

            if (difference > 1) {
              // Ha faltado por lo menos 1 día
              if (isPro) {
                final lastShieldStr = row['last_shield_used']?.toString();
                DateTime? lastShield;
                if (lastShieldStr != null)
                  lastShield = DateTime.tryParse(lastShieldStr);

                bool canUseShield = false;
                if (lastShield == null) {
                  canUseShield = true;
                } else {
                  final lastShieldDay = DateTime(
                    lastShield.year,
                    lastShield.month,
                    lastShield.day,
                  );
                  if (todayDate.difference(lastShieldDay).inDays >= 7) {
                    canUseShield = true;
                  }
                }

                if (canUseShield) {
                  print('🛡️ Streak Shield activado para usuario PRO!');
                  final yesterday = todayDate.subtract(const Duration(days: 1));
                  final yesterdayStr =
                      "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
                  final todayStr =
                      "${todayDate.year}-${todayDate.month.toString().padLeft(2, '0')}-${todayDate.day.toString().padLeft(2, '0')}";

                  await _client.execute('''
                    UPDATE users SET 
                      last_shield_used = '$yesterdayStr',
                      last_played_date = '$yesterdayStr',
                      notified_shield = 0 
                    WHERE id = '$userId'
                  ''');
                  notifiedShield = 0;
                } else {
                  print(
                    '💔 Usuario PRO perdió la racha. Escudo aún en cooldown.',
                  );
                  currentStreak = 0;
                  await _client.execute(
                    "UPDATE users SET current_streak = 0 WHERE id = '$userId'",
                  );
                }
              } else {
                print('💔 Usuario Free perdió la racha.');
                currentStreak = 0;
                await _client.execute(
                  "UPDATE users SET current_streak = 0 WHERE id = '$userId'",
                );
              }
            }
          }
        }

        // Manejo robusto de tipos (BigInt vs int) para Turso/SQLite
        int xpValue = 0;
        if (row['xp'] is BigInt)
          xpValue = (row['xp'] as BigInt).toInt();
        else if (row['xp'] is int)
          xpValue = row['xp'] as int;

        int streakValue = currentStreak;
        int ticketValue = 0;
        if (row['reward_tickets'] is BigInt)
          ticketValue = (row['reward_tickets'] as BigInt).toInt();
        else if (row['reward_tickets'] is int)
          ticketValue = row['reward_tickets'] as int;

        int bestSec = _toInt(row['best_time']);
        String bestTimeStr = '--:--';
        if (bestSec > 0) {
          final m = (bestSec ~/ 60).toString().padLeft(2, '0');
          final s = (bestSec % 60).toString().padLeft(2, '0');
          bestTimeStr = '$m:$s';
        }

        return {
          'id': row['id']?.toString() ?? '',
          'username': row['username']?.toString() ?? '',
          'name': row['name']?.toString() ?? '',
          'email': row['email']?.toString() ?? '',
          'xp': xpValue,
          'current_streak': streakValue,
          'reward_tickets': ticketValue,
          'is_pro': isPro,
          'notified_shield': notifiedShield,
          'last_shield_used': row['last_shield_used']?.toString(),
          'last_username_update': row['last_username_update']?.toString(),
          'country': row['country']?.toString(),
          'played': _toInt(row['total_played']),
          'won': _toInt(row['total_won']),
          'best_time': bestTimeStr,
        };
      } else if (userId.contains('guest_')) {
        // Retornar perfil temporal para invitados que aún no están en la DB
        return {
          'id': userId,
          'username':
              'Invitado_${userId.length > 14 ? userId.substring(userId.length - 5) : "User"}',
          'name': 'Invitado',
          'email': 'guest_$userId@devretos.com',
          'xp': 0,
          'current_streak': 0,
          'reward_tickets': 0,
          'is_pro': false,
          'notified_shield': 1,
          'played': 0,
          'won': 0,
          'best_time': '--:--',
        };
      }
      return null;
    } catch (e) {
      print('Exception getUserProfile: $e');
      return null;
    }
  }

  /// Valida la respuesta y actualiza progreso con control de límites Freemium
  Future<({bool isCorrect, int xpEarned})> submitAnswer(
    String challengeId,
    String answer,
    String userId,
    int timeSeconds, {
    bool usedHelp = false,
    String?
    knownAnswer, // Respuesta correcta pasada directamente (evita query en práctica)
  }) async {
    try {
      final String todayStr = DateTime.now().toIso8601String().substring(0, 10);

      // 0. Asegurar integridad del usuario (Crucial para Invitados por FK)
      await _client.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, current_streak, is_pro)
        VALUES ('$userId', 'guest_${userId.substring(0, 8)}', 'Invitado', 'guest_$userId@devretos.com', 0, 0, 0)
      ''');

      // 1. Metadata Gathering (Optimizado para reducir latencia de red)
      final infoSet = await _client.query('''
        SELECT 
          COALESCE(u.is_pro, 0) as is_pro,
          COALESCE(u.reward_tickets, 0) as reward_tickets,
          (SELECT attempts FROM user_sessions WHERE user_id = '$userId' AND challenge_id = '$challengeId' AND completion_date = '$todayStr') as current_attempts,
          ${knownAnswer != null ? "'$knownAnswer'" : "(SELECT correct_answer FROM challenges WHERE id = '$challengeId')"} as correct_answer,
          (SELECT 1 FROM daily_challenges WHERE display_date = '$todayStr' AND challenge_id = '$challengeId') as is_daily
        FROM users u WHERE u.id = '$userId'
      ''');

      if (infoSet.isEmpty) return (isCorrect: false, xpEarned: 0);
      final row = infoSet.first;

      final bool isPro =
          row['is_pro'] == 1 ||
          row['is_pro'] == true ||
          row['is_pro']?.toString() == '1';
      final int prevAttempts = (row['current_attempts'] as int? ?? 0);
      final int tickets = (row['reward_tickets'] as int? ?? 0);
      final bool isDaily =
          (row['is_daily'] == 1 || row['is_daily']?.toString() == '1');
      final String correctAnswerRaw = row['correct_answer']?.toString() ?? '';

      if (correctAnswerRaw.isEmpty && knownAnswer == null)
        return (isCorrect: false, xpEarned: 0);

      // 2. Control de límites Freemium
      if (!isPro) {
        if (prevAttempts >= 3) {
          if (tickets > 0) {
            print('🎟️ Usando ticket de recompensa para intento extra.');
            await _client.execute(
              "UPDATE users SET reward_tickets = reward_tickets - 1 WHERE id = '$userId'",
            );
          } else {
            print('🚫 Límite de intentos alcanzado para usuario gratuito.');
            return (isCorrect: false, xpEarned: 0);
          }
        }
      }

      // --- NORMALIZACIÓN NIVEL 1 (Estándar: Colapso de espacios) ---
      String normalize(String input) {
        return input
            .replaceAll('`', '')
            .replaceAll('"', '')
            .replaceAll("'", "")
            .replaceAll('\n', ' ')
            .replaceAll('\t', ' ')
            .replaceAll('\r', '')
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ');
      }

      // --- NORMALIZACIÓN NIVEL 2 (Súper flexible: Sin ningún espacio) ---
      String superNormalize(String input) {
        return input
            .replaceAll('`', '')
            .replaceAll('"', '')
            .replaceAll("'", "")
            .replaceAll(RegExp(r'\s+'), '') // ELIMINA TODO ESPACIO
            .trim()
            .toLowerCase();
      }

      final normCorrect = normalize(correctAnswerRaw);
      final normUser = normalize(answer);

      // Limpieza de punto final opcional
      final cleanCorrect = normCorrect.endsWith('.')
          ? normCorrect.substring(0, normCorrect.length - 1)
          : normCorrect;
      final cleanUser = normUser.endsWith('.')
          ? normUser.substring(0, normUser.length - 1)
          : normUser;

      bool isCorrect = (cleanUser == cleanCorrect);

      // SI FALLA: Intento con Super Normalización (sin espacios) para código
      if (!isCorrect) {
        final snCorrect = superNormalize(correctAnswerRaw);
        final snUser = superNormalize(answer);

        // Limpieza de punto final opcional también en SN
        final finalSNCorrect = snCorrect.endsWith('.')
            ? snCorrect.substring(0, snCorrect.length - 1)
            : snCorrect;
        final finalSNUser = snUser.endsWith('.')
            ? snUser.substring(0, snUser.length - 1)
            : snUser;

        if (finalSNUser == finalSNCorrect) {
          isCorrect = true;
          print(
            '✅ Aceptado por Super Normalización (coincidencia sin espacios).',
          );
        }
      }

      print('-----------------------------------------');
      print('🔍 ID RETO: $challengeId');
      print('🔍 DB RAW:    [$correctAnswerRaw]');
      print('🔍 NORMALIZADA: [$cleanCorrect] (len: ${cleanCorrect.length})');
      print('🔍 USUARIO:    [$cleanUser] (len: ${cleanUser.length})');
      print('🔍 RESULTADO:  ${isCorrect ? "✅ ÉXITO" : "❌ FALLO"}');
      print('-----------------------------------------');

      // 3. Calcular XP si es correcto
      int totalXpToGrant = 0;
      if (isCorrect) {
        // Configuración de rangos según el modo (usamos isDaily definido al inicio)
        final int baseXP = isDaily ? 100 : 25;
        final int speedBonus = isDaily ? 95 : 23;
        final int precisionBonus = isDaily ? 95 : 24;

        totalXpToGrant = baseXP;

        if (usedHelp) {
          if (isPro) {
            totalXpToGrant = baseXP;
          } else {
            totalXpToGrant = (timeSeconds > 300) ? 0 : 10;
          }
        } else {
          // Bono de Velocidad: < 45 segundos
          if (timeSeconds < 45) {
            totalXpToGrant += speedBonus;
          }
          // Bono de Precisión: Éxito en el primer intento
          if (prevAttempts == 0) {
            totalXpToGrant += precisionBonus;
          }
        }
      }

      // 4. Registrar en user_sessions (Unificado con XP)
      final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';
      await _client.execute('''
        INSERT INTO user_sessions (id, user_id, challenge_id, time_taken_seconds, is_success, attempts, completed_at, completion_date, xp_earned)
        VALUES ('$sessionId', '$userId', '$challengeId', $timeSeconds, ${isCorrect ? 1 : 0}, 1, CURRENT_TIMESTAMP, '$todayStr', $totalXpToGrant)
        ON CONFLICT(user_id, challenge_id) DO UPDATE SET 
          attempts = CASE 
            WHEN completion_date != '$todayStr' THEN 1 
            ELSE attempts + 1 
          END,
          time_taken_seconds = CASE 
            WHEN EXCLUDED.is_success = 1 THEN $timeSeconds 
            WHEN completion_date != '$todayStr' THEN 0
            ELSE time_taken_seconds 
          END,
          is_success = CASE 
            WHEN EXCLUDED.is_success = 1 THEN 1 
            WHEN completion_date != '$todayStr' THEN 0
            ELSE is_success 
          END,
          xp_earned = xp_earned + $totalXpToGrant,
          completed_at = CURRENT_TIMESTAMP,
          completion_date = '$todayStr'
      ''');

      if (isCorrect) {
        // 5. Actualizar usuario (XP y Racha unificado)
        await _client.execute('''
          UPDATE users SET 
            xp = xp + $totalXpToGrant,
            current_streak = CASE 
              WHEN $isDaily AND COALESCE(last_played_date, '') != '$todayStr'
              THEN CASE 
                WHEN last_played_date = DATE('$todayStr', '-1 day') THEN current_streak + 1
                ELSE 1
              END
              ELSE current_streak 
            END,
            last_played_date = CASE WHEN $isDaily THEN '$todayStr' ELSE last_played_date END
          WHERE id = '$userId'
        ''');

        print('🏆 TOTAL XP OTORGADO: $totalXpToGrant');
        return (isCorrect: true, xpEarned: totalXpToGrant);
      }

      return (isCorrect: isCorrect, xpEarned: 0);
    } catch (e) {
      print('Exception submitAnswer: $e');
      return (isCorrect: false, xpEarned: 0);
    }
  }

  /// Marca un reto como abandonado (fallado permanentemente)
  Future<void> abandonChallenge(String challengeId, String userId, int timeSeconds) async {
    try {
      final String todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';

      // Asegurar integridad del usuario
      await _client.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, current_streak, is_pro)
        VALUES ('$userId', 'guest_${userId.substring(0, 8)}', 'Invitado', 'guest_$userId@devretos.com', 0, 0, 0)
      ''');

      await _client.execute('''
        INSERT INTO user_sessions (id, user_id, challenge_id, time_taken_seconds, is_success, attempts, completed_at, completion_date, xp_earned)
        VALUES ('$sessionId', '$userId', '$challengeId', $timeSeconds, -1, 3, CURRENT_TIMESTAMP, '$todayStr', 0)
        ON CONFLICT(user_id, challenge_id) DO UPDATE SET 
          attempts = 3,
          time_taken_seconds = $timeSeconds,
          is_success = -1,
          completed_at = CURRENT_TIMESTAMP,
          completion_date = '$todayStr'
      ''');
      
      // Al abandonar no se rompe la racha de inmediato aquí, porque la racha se rompe por inactividad diaria.
      // Pero sí actualizamos last_played_date para que cuente como que interactuó (aunque falló).
      await _client.execute('''
        UPDATE users SET 
          last_played_date = CASE 
            WHEN EXISTS (SELECT 1 FROM daily_challenges WHERE display_date = '$todayStr' AND challenge_id = '$challengeId') 
            THEN '$todayStr' 
            ELSE last_played_date 
          END
        WHERE id = '$userId'
      ''');

      print('🚩 Reto $challengeId abandonado por usuario $userId');
    } catch (e) {
      print('Exception abandonChallenge: $e');
    }
  }

  /// Trae el ranking de usuarios basado únicamente en el XP ganado HOY (horario UTC del servidor)
  Future<List<Map<String, dynamic>>> getDailyRanking() async {
    try {
      final minWait = Future.delayed(const Duration(milliseconds: 400));
      final queryJob = _client.query('''
        SELECT u.id, u.username, u.name, SUM(us.xp_earned) as xp, u.country, u.is_pro 
        FROM users u 
        JOIN user_sessions us ON u.id = us.user_id 
        WHERE us.completion_date = '${DateTime.now().toIso8601String().substring(0, 10)}'
        GROUP BY u.id 
        ORDER BY xp DESC 
        LIMIT 20
      ''');

      final results = await Future.wait([queryJob, minWait]);
      final resultSet = results[0] as List<Map<String, dynamic>>;

      return resultSet
          .map(
            (row) => {
              'id': row['id']?.toString() ?? '',
              'username': row['username']?.toString() ?? 'User',
              'name': row['name']?.toString() ?? '',
              'xp': (row['xp'] as int? ?? 0),
              'country': row['country']?.toString() ?? 'Bolivia',
              'is_pro':
                  (row['is_pro'] == 1 ||
                  row['is_pro'] == true ||
                  row['is_pro']?.toString() == '1'),
            },
          )
          .toList();
    } catch (e) {
      print('Exception getDailyRanking: $e');
      return [];
    }
  }

  /// Trae el ranking global de usuarios por XP
  Future<List<Map<String, dynamic>>> getGlobalRanking() async {
    try {
      // Espera mínima profesional de 400ms
      final minWait = Future.delayed(const Duration(milliseconds: 400));
      final queryJob = _client.query('''
        SELECT id, username, name, xp, country, is_pro FROM users 
        ORDER BY xp DESC 
        LIMIT 20
      ''');

      final results = await Future.wait([queryJob, minWait]);
      final resultSet = results[0] as List<Map<String, dynamic>>;
      return resultSet
          .map(
            (row) => {
              'id': row['id']?.toString() ?? '',
              'username': row['username']?.toString() ?? 'User',
              'name': row['name']?.toString() ?? '',
              'xp': (row['xp'] as int? ?? 0),
              'country': row['country']?.toString() ?? 'Bolivia',
              'is_pro':
                  (row['is_pro'] == 1 ||
                  row['is_pro'] == true ||
                  row['is_pro']?.toString() == '1'),
            },
          )
          .toList();
    } catch (e) {
      print('Exception getGlobalRanking: $e');
      return [];
    }
  }

  /// Actualiza el username si han pasado al menos 7 días desde el último cambio
  Future<String?> updateUsername(String userId, String newUsername) async {
    try {
      final userSet = await _client.query(
        "SELECT last_username_update FROM users WHERE id = '$userId'",
      );
      if (userSet.isEmpty) return 'Usuario no encontrado.';

      final lastUpdateRaw = userSet.first['last_username_update'];
      if (lastUpdateRaw != null) {
        final lastUpdate = DateTime.tryParse(lastUpdateRaw.toString());
        if (lastUpdate != null) {
          final difference = DateTime.now().difference(lastUpdate);
          if (difference.inDays < 7) {
            final diasRestantes = 7 - difference.inDays;
            return 'Debes esperar $diasRestantes días para volver a cambiar tu nombre de usuario.';
          }
        }
      }

      // Check if username is already taken
      final safeUsername = newUsername.replaceAll("'", "''");
      final dupCheck = await _client.query(
        "SELECT id FROM users WHERE username = '$safeUsername' AND id != '$userId'",
      );
      if (dupCheck.isNotEmpty) return 'El nombre de usuario ya está en uso.';

      final now = DateTime.now().toIso8601String();
      await _client.execute(
        "UPDATE users SET username = '$safeUsername', last_username_update = '$now' WHERE id = '$userId'",
      );
      return null; // Null significa éxito sin errores
    } catch (e) {
      print('Exception updateUsername: $e');
      return 'Error al actualizar el nombre de usuario.';
    }
  }

  /// Verifica si un username está disponible (no lo usa nadie más)
  Future<bool> isUsernameAvailable(
    String username,
    String currentUserId,
  ) async {
    try {
      if (username.trim().isEmpty) return false;
      final safeUsername = username.trim().replaceAll("'", "''");
      final dupCheck = await _client.query(
        "SELECT id FROM users WHERE username = '$safeUsername' AND id != '$currentUserId'",
      );
      return dupCheck.isEmpty;
    } catch (e) {
      print('Error in isUsernameAvailable: $e');
      return false;
    }
  }

  /// Actualiza el país del usuario en Turso
  Future<bool> updateCountry(String userId, String country) async {
    try {
      final safeCountry = country.replaceAll("'", "''");
      await _client.execute(
        "UPDATE users SET country = '$safeCountry' WHERE id = '$userId'",
      );
      print('✅ País actualizado a $country para el usuario $userId');
      return true;
    } catch (e) {
      print('Exception updateCountry: $e');
      return false;
    }
  }

  /// Obtiene la lista dinámica de tecnologías para la vista de práctica
  Future<List<String>> getTechnologies() async {
    try {
      final resultSet = await _client.query('''
        SELECT DISTINCT technology FROM challenges WHERE technology IS NOT NULL
      ''');

      return resultSet.map((row) => row['technology'].toString()).toList();
    } catch (e) {
      print('Exception getTechnologies: $e');
      return [];
    }
  }

  /// Migra los datos de un usuario invitado a una cuenta real
  Future<void> migrateGuestData(String guestId, String realUserId) async {
    try {
      print('🔄 Migrando datos de $guestId a $realUserId...');

      // 1. Obtener datos del invitado
      final guestData = await _client.query(
        "SELECT xp, current_streak FROM users WHERE id = '$guestId'",
      );

      if (guestData.isNotEmpty) {
        final guestXp = guestData.first['xp'] as int? ?? 0;
        final guestStreak = guestData.first['current_streak'] as int? ?? 0;

        // 2. Actualizar el usuario real sumando XP y tomando la mejor racha
        await _client.execute('''
          UPDATE users SET 
            xp = xp + $guestXp,
            current_streak = CASE WHEN $guestStreak > current_streak THEN $guestStreak ELSE current_streak END
          WHERE id = '$realUserId'
        ''');
        print('✅ XP y Racha migrados.');
      }

      // 3. Vincular todas las sesiones al nuevo usuario
      await _client.execute('''
        UPDATE user_sessions SET user_id = '$realUserId' WHERE user_id = '$guestId'
      ''');
      print('✅ Sesiones de reto vinculadas.');

      // 4. Eliminar el registro del invitado
      await _client.execute("DELETE FROM users WHERE id = '$guestId'");
      print('✅ Registro de invitado eliminado.');
    } catch (e) {
      print('❌ Error en migrateGuestData: $e');
      rethrow;
    }
  }

  /// Evaluador Freemium: Decide si el usuario puede jugar un reto nuevo
  Future<bool> canUserPlayChallenge(String userId) async {
    try {
      final userSet = await _client.query(
        "SELECT is_pro, reward_tickets FROM users WHERE id = '$userId'",
      );
      if (userSet.isEmpty) return true; // Usuario nuevo/invitado puede jugar

      final isPro = userSet.first['is_pro'] == 1;
      final ticketsVal = userSet.first['reward_tickets'];
      final tickets = ticketsVal is BigInt
          ? ticketsVal.toInt()
          : (ticketsVal as int? ?? 0);

      if (isPro) return true; // Acceso Total VIP
      if (tickets > 0) return true; // Acceso temporal via Ad Recompensado

      // Límite de 3 Prácticas Diarias (Excluyendo Retos Diarios)
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final countSet = await _client.query('''
        SELECT COUNT(*) as count FROM user_sessions 
        WHERE user_id = '$userId' 
          AND completion_date >= '$todayStr'
          AND challenge_id NOT IN (SELECT challenge_id FROM daily_challenges WHERE display_date = '$todayStr')
      ''');

      final countVal = countSet.first['count'];
      final todayPracticeCount = countVal is BigInt
          ? countVal.toInt()
          : (countVal as int? ?? 0);

      return todayPracticeCount < 3;
    } catch (e) {
      print('Exception canUserPlayChallenge: $e');
      return false;
    }
  }

  /// Otorga Ticket AdMob tras anuncio validado
  Future<void> grantAdRewardTicket(String userId) async {
    try {
      // Asegurar que el usuario exista (especialmente para invitados)
      await _client.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, current_streak, is_pro)
        VALUES ('$userId', 'guest_${userId.length > 8 ? userId.substring(userId.length - 5) : "user"}', 'Invitado', 'guest_$userId@devretos.com', 0, 0, 0)
      ''');

      await _client.execute(
        "UPDATE users SET reward_tickets = reward_tickets + 1 WHERE id = '$userId'",
      );
      print('🎟️ Ticket AdMob otorgado en Turso');
    } catch (e) {
      print('Exception grantAdRewardTicket: $e');
    }
  }

  /// Obtiene estadísticas reales de retos para el perfil (Exclusivo de Retos Diarios)
  Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      final resultSet = await _client.query('''
        SELECT 
            COUNT(*) as total_played,
            COUNT(CASE WHEN is_success = 1 THEN 1 END) as total_won,
            MIN(CASE WHEN is_success = 1 THEN time_taken_seconds END) as best_time
        FROM user_sessions us
        WHERE us.user_id = '$userId'
        AND EXISTS (SELECT 1 FROM daily_challenges dc WHERE dc.challenge_id = us.challenge_id AND dc.display_date = us.completion_date)
      ''');

      if (resultSet.isEmpty) {
        return {'played': 0, 'won': 0, 'best_time': '--:--'};
      }

      final row = resultSet.first;
      final played = row['total_played'] is BigInt
          ? (row['total_played'] as BigInt).toInt()
          : (row['total_played'] as int? ?? 0);
      final won = row['total_won'] is BigInt
          ? (row['total_won'] as BigInt).toInt()
          : (row['total_won'] as int? ?? 0);
      final bestSec = row['best_time'] is BigInt
          ? (row['best_time'] as BigInt).toInt()
          : (row['best_time'] as int? ?? 0);

      String bestTimeStr = '--:--';
      if (bestSec > 0) {
        final m = (bestSec ~/ 60).toString().padLeft(2, '0');
        final s = (bestSec % 60).toString().padLeft(2, '0');
        bestTimeStr = '$m:$s';
      }

      return {'played': played, 'won': won, 'best_time': bestTimeStr};
    } catch (e) {
      print('Exception getUserStats: $e');
      return {'played': 0, 'won': 0, 'best_time': '--:--'};
    }
  }

  /// Búsqueda Global en Caché (Turso). Si no existe, invoca IA.
  Future<Map<String, dynamic>?> getOrGeneratePracticeChallenge(
    String technology,
    String level,
    String userId,
    AiChallengeService aiService,
  ) async {
    try {
      // Espera mínima profesional de 400ms
      final minWait = Future.delayed(const Duration(milliseconds: 400));

      // 1. Buscar en Turso un reto no completado exitosamente por este usuario
      final queryJob = _client.query('''
        SELECT * FROM challenges 
        WHERE technology = '$technology' 
          AND level = '$level'
          AND id NOT IN (SELECT challenge_id FROM user_sessions WHERE user_id = '$userId' AND is_success = 1)
        ORDER BY RANDOM() LIMIT 1
      ''');

      final results = await Future.wait([queryJob, minWait]);
      final resultSet = results[0] as List<Map<String, dynamic>>;

      if (resultSet.isNotEmpty) {
        print('✅ Caché Turso: Reto encontrado localmente (Hit)');
        final row = resultSet.first;
        return {
          'id': row['id']?.toString() ?? '',
          'title': row['title']?.toString() ?? '',
          'question': row['question']?.toString() ?? '',
          'code_snippet': row['code_snippet']?.toString() ?? '',
          'correct_answer': row['correct_answer']?.toString() ?? '',
          'technology': row['technology']?.toString() ?? '',
          'level': row['level']?.toString() ?? '',
        };
      }

      // 2. Miss (Fallo) - Generar con IA
      print(
        '⏳ Reto de $technology - $level no encontrado. Solicitando a las APIs de IA...',
      );
      final aiGenerated = await aiService.generateChallenge(technology, level);

      if (aiGenerated == null) return null;

      // 3. Guardar en Turso (El toque maestro para poblar gratuitamente)
      final newId = 'c_${DateTime.now().millisecondsSinceEpoch}';

      // Sanitizar contenido JSON retornado por la IA para evitar inyección SQLite básica en el insert local:
      final t = aiGenerated['title'].toString().replaceAll("'", "''");
      final q = aiGenerated['question'].toString().replaceAll("'", "''");
      final c = aiGenerated['code_snippet'].toString().replaceAll("'", "''");
      final a = aiGenerated['correct_answer'].toString().replaceAll("'", "''");

      await _client.execute('''
        INSERT INTO challenges (id, title, question, code_snippet, correct_answer, technology, level, is_premium)
        VALUES (
          '$newId', 
          '$t', 
          '$q', 
          '$c', 
          '$a', 
          '$technology', 
          '$level', 
          0
        )
      ''');

      print('💾 Reto Inteligente guardado en Turso colaborativamente!');

      return {
        'id': newId,
        'title': aiGenerated['title'],
        'question': aiGenerated['question'],
        'code_snippet': aiGenerated['code_snippet'],
        'correct_answer': aiGenerated['correct_answer'],
        'technology': technology,
        'level': level,
      };
    } catch (e) {
      print('Exception getOrGeneratePracticeChallenge: $e');
      return null;
    }
  }

  /// Obtiene la respuesta correcta de un reto (Solo llamar tras ver anuncio)
  Future<String?> getCorrectAnswer(String challengeId) async {
    try {
      final resultSet = await _client.query(
        "SELECT correct_answer FROM challenges WHERE id = '$challengeId'",
      );
      if (resultSet.isNotEmpty) {
        return resultSet.first['correct_answer']?.toString();
      }
      return null;
    } catch (e) {
      print('Error getCorrectAnswer: $e');
      return null;
    }
  }

  /// Obtiene el historial de sesiones del usuario, opcionalmente filtrado por tipo
  Future<List<Map<String, dynamic>>> getUserSessions(
    String userId, {
    bool? onlyDaily,
    int limit = 20,
  }) async {
    try {
      String filterClause = "";
      if (onlyDaily == true) {
        filterClause =
            "AND EXISTS (SELECT 1 FROM daily_challenges dc WHERE dc.challenge_id = us.challenge_id AND dc.display_date = us.completion_date)";
      } else if (onlyDaily == false) {
        filterClause =
            "AND NOT EXISTS (SELECT 1 FROM daily_challenges dc WHERE dc.challenge_id = us.challenge_id AND dc.display_date = us.completion_date)";
      }

      final resultSet = await _client.query('''
        SELECT us.*, c.title, c.technology, c.level 
        FROM user_sessions us
        JOIN challenges c ON us.challenge_id = c.id
        WHERE us.user_id = '$userId'
        $filterClause
        ORDER BY us.completed_at DESC
        LIMIT $limit
      ''');

      return resultSet
          .map(
            (row) => {
              'id': row['id']?.toString() ?? '',
              'challenge_id': row['challenge_id']?.toString() ?? '',
              'time_taken_seconds': (row['time_taken_seconds'] as int? ?? 0),
              'is_success': (row['is_success'] as int? ?? 0),
              'completed_at': row['completed_at']?.toString() ?? '',
              'title': row['title']?.toString() ?? 'Reto',
              'technology': row['technology']?.toString() ?? '',
              'level': row['level']?.toString() ?? '',
              'attempts': (row['attempts'] as int? ?? 1),
            },
          )
          .toList();
    } catch (e) {
      print('Exception getUserSessions: $e');
      return [];
    }
  }

  /// Inserta retos profesionales iniciales si la tabla de retos está vacía.
  Future<void> _seedInitialChallenges() async {
    try {
      final countSet = await _client.query(
        "SELECT COUNT(*) as total FROM challenges",
      );

      final total =
          int.tryParse(countSet.first['total']?.toString() ?? '0') ?? 0;
      if (total > 5) return;

      print('🌱 Sembrando retos profesionales iniciales...');

      final seedChallenges = [
        [
          'seed_01',
          'Python: Listas',
          '¿Cómo se añade un elemento al final de una lista?',
          'lista....(item)',
          'append',
          'Python',
          'PRINCIPIANTE',
          0,
        ],
        [
          'seed_02',
          'JS: Asincronía',
          '¿Qué palabra acompaña a "async" para esperar una promesa?',
          'async function x() { ... task(); }',
          'await',
          'JavaScript',
          'INTERMEDIO',
          0,
        ],
        [
          'seed_03',
          'SQL: Filtros',
          '¿Qué cláusula se usa para filtrar resultados?',
          'SELECT * FROM users ... id = 1;',
          'WHERE',
          'SQL',
          'PRINCIPIANTE',
          0,
        ],
        [
          'seed_04',
          'Dart: Inferencia',
          '¿Qué palabra se usa para inferencia de tipo local?',
          '... name = "Dev";',
          'var',
          'Dart',
          'PRINCIPIANTE',
          0,
        ],
        [
          'seed_05',
          'Flutter: Widgets',
          '¿Cuál es el widget base para una app con Material Design?',
          'class App extends ... { ... }',
          'MaterialApp',
          'Flutter',
          'PRINCIPIANTE',
          0,
        ],
        [
          'seed_06',
          'CSS: Flexbox',
          'Propiedad para alinear items en el eje principal:',
          'display: flex; ...: center;',
          'justify-content',
          'CSS',
          'INTERMEDIO',
          0,
        ],
        [
          'seed_11',
          'Docker: Imagen',
          'Comando para construir una imagen desde un Dockerfile:',
          'docker ... -t mi-app .',
          'build',
          'Docker',
          'INTERMEDIO',
          0,
        ],
        [
          'seed_12',
          'Git: Ramas',
          'Comando para cambiar de rama:',
          'git ... nueva-rama',
          'checkout',
          'Git',
          'PRINCIPIANTE',
          0,
        ],
        [
          'seed_14',
          'TypeScript: Tipos',
          '¿Cómo se define un valor que puede ser de cualquier tipo?',
          'let x: ... = 10;',
          'any',
          'TypeScript',
          'INTERMEDIO',
          0,
        ],
        [
          'seed_16',
          'Kotlin: Nulabilidad',
          'Operador para llamada segura (safe call):',
          'user...name',
          '?.',
          'Kotlin',
          'INTERMEDIO',
          0,
        ],
        [
          'seed_18',
          'Rust: Mutabilidad',
          'Palabra para declarar una variable mutable:',
          'let ... x = 5;',
          'mut',
          'Rust',
          'AVANZADO',
          0,
        ],
        [
          'seed_20',
          'Linux: Permisos',
          'Comando para cambiar permisos de un archivo:',
          '... 755 script.sh',
          'chmod',
          'Linux',
          'AVANZADO',
          0,
        ],
      ];

      for (var c in seedChallenges) {
        await _client.execute('''
          INSERT OR REPLACE INTO challenges (id, title, question, code_snippet, correct_answer, technology, level, is_premium)
          VALUES ('${c[0]}', '${c[1]}', '${c[2]}', '${c[3]}', '${c[4]}', '${c[5]}', '${c[6]}', ${c[7]})
        ''');
      }
      print('✅ Retos semilla cargados correctamente.');
    } catch (e) {}
  }

  /// Obtiene el progreso de los últimos 7 días (para el calendario de racha)
  Future<List<int>> getWeeklyProgress(String userId) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final sevenDaysAgoStr = sevenDaysAgo.toIso8601String().substring(0, 10);

      // Una sola consulta para toda la semana
      final resultSet = await _client.query('''
        SELECT completion_date, MAX(is_success) as status
        FROM user_sessions 
        WHERE user_id = '$userId' 
        AND completion_date >= '$sevenDaysAgoStr'
        AND EXISTS (SELECT 1 FROM daily_challenges dc WHERE dc.challenge_id = user_sessions.challenge_id AND dc.display_date = user_sessions.completion_date)
        GROUP BY completion_date
      ''');

      // Mapear resultados
      final Map<String, int> dateStatus = {
        for (var row in resultSet)
          row['completion_date'].toString(): _toInt(row['status'])
      };

      final List<int> progress = [];
      for (int i = 0; i < 7; i++) {
        final day = now.subtract(Duration(days: i));
        final dayStr = day.toIso8601String().substring(0, 10);
        progress.add(dateStatus[dayStr] ?? 0);
      }

      return progress;
    } catch (e) {
      print('Exception getWeeklyProgress: $e');
      return List.filled(7, 0);
    }
  }

  /// Limpia TODAS las tablas para iniciar en blanco. Úsalo con cuidado.
  Future<void> _clearAllData() async {
    try {
      print(
        '⚠️ ADVERTENCIA: Vaciando registros de la base de datos de producción...',
      );
      await _client.execute('DELETE FROM user_sessions;');
      await _client.execute('DELETE FROM daily_challenges;');
      await _client.execute('DELETE FROM challenges;');
      await _client.execute('DELETE FROM users;');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('db_initialized', false);

      print('✅ Base de datos limpiada y estado resetado.');
    } catch (e) {
      print('❌ Error al limpiar base de datos: $e');
    }
  }

  /// Marca que el usuario ya vió el popup del Shield y no debe volver a mostrarse hoy.
  Future<void> acknowledgeShield(String userId) async {
    try {
      await _client.execute(
        "UPDATE users SET notified_shield = 1 WHERE id = '$userId'",
      );
    } catch (e) {
      print('Error acknowledgeShield: $e');
    }
  }

  /// Guarda un reto generado por IA en la base de datos
  Future<void> saveAiChallenge(
    Map<String, dynamic> challenge,
    String userId,
  ) async {
    try {
      await _client.execute('''
        INSERT INTO challenges (id, title, question, code_snippet, correct_answer, technology, level, is_ai, creator_id)
        VALUES (
          '${challenge['id']}',
          '${challenge['title'].toString().replaceAll("'", "''")}',
          '${challenge['question'].toString().replaceAll("'", "''")}',
          '${challenge['code_snippet'].toString().replaceAll("'", "''")}',
          '${challenge['correct_answer'].toString().replaceAll("'", "''")}',
          '${challenge['technology']}',
          '${challenge['level']}',
          1,
          '$userId'
        )
      ''');
    } catch (e) {
      print('Error saveAiChallenge: $e');
    }
  }

  // ===========================================================================
  // SECCIÓN PRO: ESTADÍSTICAS Y DASHBOARD
  // ===========================================================================

  Future<List<Map<String, dynamic>>> getWeeklyXPProgress(String userId) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 6));
      final sevenDaysAgoStr = DateFormat('yyyy-MM-dd').format(sevenDaysAgo);

      final resultSet = await _client.query('''
        SELECT completion_date, SUM(xp_earned) as total_xp
        FROM user_sessions
        WHERE user_id = '$userId' 
          AND completion_date >= '$sevenDaysAgoStr'
          AND is_success = 1
        GROUP BY completion_date
        ORDER BY completion_date ASC
      ''');

      final Map<String, int> xpMap = {};
      for (var row in resultSet) {
        xpMap[row['completion_date'].toString()] =
            (row['total_xp'] as int? ?? 0);
      }

      final List<Map<String, dynamic>> results = [];
      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final dayStr = DateFormat('yyyy-MM-dd').format(day);
        results.add({'day': dayStr, 'xp': xpMap[dayStr] ?? 0});
      }

      return results;
    } catch (e) {
      print('Error getWeeklyXPProgress: $e');
      return [];
    }
  }

  /// Obtiene el dominio por tecnología (conteo de retos ganados)
  Future<Map<String, double>> getTechnologyMastery(String userId) async {
    try {
      final resultSet = await _client.query('''
        SELECT c.technology, COUNT(*) as count
        FROM user_sessions us
        JOIN challenges c ON us.challenge_id = c.id
        WHERE us.user_id = '$userId' AND us.is_success = 1
        GROUP BY c.technology
      ''');

      final Map<String, double> mastery = {};
      for (var row in resultSet) {
        mastery[row['technology'].toString()] = (row['count'] as int? ?? 0)
            .toDouble();
      }
      return mastery;
    } catch (e) {
      print('Error getTechnologyMastery: $e');
      return {};
    }
  }

  /// Obtiene estadísticas de precisión (Aciertos vs Errores)
  Future<Map<String, int>> getUserAccuracyStats(String userId) async {
    try {
      final resultSet = await _client.query('''
        SELECT 
          SUM(CASE WHEN is_success = 1 THEN 1 ELSE 0 END) as successes,
          SUM(CASE WHEN is_success = 0 THEN 1 ELSE 0 END) as failures
        FROM user_sessions
        WHERE user_id = '$userId'
      ''');

      if (resultSet.isNotEmpty) {
        final row = resultSet.first;
        return {
          'successes': (row['successes'] as int? ?? 0),
          'failures': (row['failures'] as int? ?? 0),
        };
      }
      return {'successes': 0, 'failures': 0};
    } catch (e) {
      print('Error getUserAccuracyStats: $e');
      return {'successes': 0, 'failures': 0};
    }
  }

  /// Obtiene el historial de retos generados por IA
  Future<List<Map<String, dynamic>>> getAiChallengeHistory(
    String userId,
  ) async {
    try {
      final resultSet = await _client.query('''
        SELECT c.*, us.is_success, us.completed_at as solved_at
        FROM challenges c
        LEFT JOIN user_sessions us ON c.id = us.challenge_id AND us.user_id = '$userId'
        WHERE c.is_ai = 1 AND (c.creator_id = '$userId' OR us.user_id = '$userId')
        ORDER BY c.created_at DESC
      ''');

      return resultSet
          .map(
            (row) => {
              'id': row['id']?.toString() ?? '',
              'title': row['title']?.toString() ?? '',
              'technology': row['technology']?.toString() ?? '',
              'level': row['level']?.toString() ?? '',
              'is_success': row['is_success'] == 1,
              'created_at': row['created_at']?.toString() ?? '',
            },
          )
          .toList();
    } catch (e) {
      print('Error getAiChallengeHistory: $e');
      return [];
    }
  }

  /// Obtiene un reto específico por su ID
  Future<Map<String, dynamic>?> getChallengeById(String challengeId) async {
    try {
      final resultSet = await _client.query(
        "SELECT * FROM challenges WHERE id = '$challengeId'",
      );
      if (resultSet.isNotEmpty) {
        return Map<String, dynamic>.from(resultSet.first);
      }
      return null;
    } catch (e) {
      print('Error getChallengeById: $e');
      return null;
    }
  }
}

final retosRepositoryProvider = Provider<RetosRepository>((ref) {
  final client = ref.watch(tursoClientProvider);
  return RetosRepository(client);
});

final userSessionsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = ref.watch(retosRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  final guestId = ref.watch(guestIdProvider);
  final userId = user?.id ?? guestId;
  final limit = (user?.isPro ?? false) ? 100 : 20;
  return repo.getUserSessions(userId, limit: limit);
});

final dailySessionsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = ref.watch(retosRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  final guestId = ref.watch(guestIdProvider);
  final userId = user?.id ?? guestId;
  final limit = (user?.isPro ?? false) ? 100 : 20;
  return repo.getUserSessions(userId, onlyDaily: true, limit: limit);
});

final practiceSessionsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = ref.watch(retosRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  final guestId = ref.watch(guestIdProvider);
  final userId = user?.id ?? guestId;
  final limit = (user?.isPro ?? false) ? 100 : 20;
  return repo.getUserSessions(userId, onlyDaily: false, limit: limit);
});

final dailyChallengesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = ref.watch(retosRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  final guestId = ref.watch(guestIdProvider);
  final userId = user?.id ?? guestId;
  return repo.getDailyChallenges(userId);
});

final technologiesProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.watch(retosRepositoryProvider);
  return repo.getTechnologies();
});

final globalRankingProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = ref.watch(retosRepositoryProvider);
  return repo.getGlobalRanking();
});

final dailyRankingProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = ref.watch(retosRepositoryProvider);
  return repo.getDailyRanking();
});

final userProfileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final repo = ref.watch(retosRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  final guestId = ref.watch(guestIdProvider);
  final userId = user?.id ?? guestId;
  return repo.getUserProfile(userId);
});

final userStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(retosRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  final guestId = ref.watch(guestIdProvider);
  final userId = user?.id ?? guestId;
  return repo.getUserStats(userId);
});

final weeklyProgressProvider = FutureProvider<List<int>>((ref) async {
  final repo = ref.watch(retosRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  final guestId = ref.watch(guestIdProvider);
  final userId = user?.id ?? guestId;
  return repo.getWeeklyProgress(userId);
});
