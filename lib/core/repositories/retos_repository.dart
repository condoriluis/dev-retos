import 'package:dev_retos/core/providers/guest_provider.dart';
import 'package:libsql_dart/libsql_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/seed_challenges.dart';
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

  Future<void> deleteUserAccount(String userId) async {
    print('DEBUG DB: Eliminando datos del usuario $userId...');
    await _client.execute(
      "DELETE FROM user_sessions WHERE user_id = '$userId'",
    );
    await _client.execute("DELETE FROM users WHERE id = '$userId'");
  }

  Future<void> initDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDbInitialized = prefs.getBool('db_initialized') ?? false;

      // Activa esta línea solo UNA vez para limpiar todo antes del lanzamiento con F5
      // await clearAllData();

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
          last_username_update DATETIME,
          last_played_date DATE,
          last_shield_used DATE,
          notified_shield INTEGER DEFAULT 1
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
          is_ai INTEGER DEFAULT 0,
          creator_id TEXT,
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
          xp_earned INTEGER DEFAULT 0,
          completion_date DATE,
          is_practice INTEGER DEFAULT 0,
          FOREIGN KEY(user_id) REFERENCES users(id),
          FOREIGN KEY(challenge_id) REFERENCES challenges(id),
          UNIQUE(user_id, challenge_id)
        );
      ''');
        print('DEBUG DB: Tabla user_sessions verificada/creada.');

        await prefs.setBool('db_initialized', true);
        print('DEBUG DB: Tablas base de datos inicializadas.');
      }

      try {
        await _client.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_sessions_stats ON user_sessions (user_id, is_success, completion_date)',
        );
      } catch (_) {}

      await _seedInitialChallenges();

      final List<String> last7Days = List.generate(7, (i) {
        final now = DateTime.now();
        final day = DateTime(now.year, now.month, now.day - i);
        return "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
      });

      final String datesIn = last7Days.map((d) => "'$d'").join(',');
      final existingDailies = await _client.query(
        "SELECT display_date FROM daily_challenges WHERE display_date IN ($datesIn)",
      );

      final Set<String> existingDates = existingDailies
          .map((row) => row['display_date'].toString())
          .toSet();

      for (final dateStr in last7Days) {
        if (!existingDates.contains(dateStr)) {
          final randomChallenges = await _client.query(
            "SELECT id FROM challenges ORDER BY RANDOM() LIMIT 1",
          );
          if (randomChallenges.isNotEmpty) {
            final cid = randomChallenges.first['id'].toString();
            await _client.execute(
              "INSERT OR IGNORE INTO daily_challenges (display_date, challenge_id) VALUES ('$dateStr', '$cid')",
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
                  row['is_completed'] == 1 ||
                  row['is_completed'] == '1' ||
                  row['is_completed'] == -1 ||
                  row['is_completed'] == '-1',
              'is_abandoned':
                  row['is_completed'] == -1 || row['is_completed'] == '-1',
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
          COALESCE((SELECT COUNT(*) FROM user_sessions us WHERE us.user_id = u.id AND us.is_practice = 0), 0) as total_played,
          COALESCE((SELECT COUNT(*) FROM user_sessions us WHERE us.user_id = u.id AND us.is_practice = 0 AND us.is_success = 1), 0) as total_won,
          COALESCE((SELECT MIN(us.time_taken_seconds) FROM user_sessions us WHERE us.user_id = u.id AND us.is_practice = 0 AND us.is_success = 1), 0) as best_time
        FROM users u 
        WHERE u.id = '$userId'
      ''');

      final resultSet = await queryJob;

      final elapsed = DateTime.now().difference(start);
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
                  final yesterday = DateTime(
                    todayDate.year,
                    todayDate.month,
                    todayDate.day - 1,
                  );
                  final yesterdayStr =
                      "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

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
    String? knownAnswer,
    bool isPractice = false,
  }) async {
    try {
      final String todayStr = DateTime.now().toIso8601String().substring(0, 10);

      await _client.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, current_streak, is_pro)
        VALUES ('$userId', 'guest_${userId.substring(0, 8)}', 'Invitado', 'guest_$userId@devretos.com', 0, 0, 0)
      ''');
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
            .replaceAll(RegExp(r'\s+'), '')
            .trim()
            .toLowerCase();
      }

      final normCorrect = normalize(correctAnswerRaw);
      final normUser = normalize(answer);

      final cleanCorrect = normCorrect.endsWith('.')
          ? normCorrect.substring(0, normCorrect.length - 1)
          : normCorrect;
      final cleanUser = normUser.endsWith('.')
          ? normUser.substring(0, normUser.length - 1)
          : normUser;

      bool isCorrect = (cleanUser == cleanCorrect);

      if (!isCorrect) {
        final snCorrect = superNormalize(correctAnswerRaw);
        final snUser = superNormalize(answer);

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
          if (timeSeconds < 45) {
            totalXpToGrant += speedBonus;
          }
          if (prevAttempts == 0) {
            totalXpToGrant += precisionBonus;
          }
        }
      }

      // 4. Registrar en user_sessions (Unificado con XP)
      final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';

      await _client.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, current_streak, is_pro)
        VALUES ('$userId', 'guest_${userId.substring(0, 8)}', 'Invitado', 'guest_$userId@devretos.com', 0, 0, 0)
      ''');

      await _client.execute('''
        INSERT INTO user_sessions (id, user_id, challenge_id, time_taken_seconds, is_success, attempts, completed_at, completion_date, xp_earned, is_practice)
        VALUES ('$sessionId', '$userId', '$challengeId', $timeSeconds, ${isCorrect ? 1 : 0}, 1, CURRENT_TIMESTAMP, '$todayStr', $totalXpToGrant, ${isPractice ? 1 : 0})
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
          completion_date = '$todayStr',
          is_practice = ${isPractice ? 1 : 0}
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

  Future<void> abandonChallenge(
    String challengeId,
    String userId,
    int timeSeconds, {
    bool isPractice = false,
  }) async {
    try {
      final String todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final sessionId = 'sess_${DateTime.now().millisecondsSinceEpoch}';

      await _client.execute('''
        INSERT OR IGNORE INTO users (id, username, name, email, xp, current_streak, is_pro)
        VALUES ('$userId', 'guest_${userId.substring(0, 8)}', 'Invitado', 'guest_$userId@devretos.com', 0, 0, 0)
      ''');

      await _client.execute('''
        INSERT INTO user_sessions (id, user_id, challenge_id, time_taken_seconds, is_success, attempts, completed_at, completion_date, xp_earned, is_practice)
        VALUES ('$sessionId', '$userId', '$challengeId', $timeSeconds, -1, 3, CURRENT_TIMESTAMP, '$todayStr', 0, ${isPractice ? 1 : 0})
        ON CONFLICT(user_id, challenge_id) DO UPDATE SET 
          attempts = 3,
          time_taken_seconds = $timeSeconds,
          is_success = -1,
          completed_at = CURRENT_TIMESTAMP,
          completion_date = '$todayStr',
          is_practice = ${isPractice ? 1 : 0}
      ''');

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

  Future<List<Map<String, dynamic>>> getDailyRanking() async {
    try {
      final minWait = Future.delayed(const Duration(milliseconds: 400));
      final queryJob = _client.query('''
        SELECT u.id, u.username, u.name, SUM(us.xp_earned) as xp, u.country, u.is_pro 
        FROM users u 
        JOIN user_sessions us ON u.id = us.user_id 
        WHERE us.completion_date = '${DateTime.now().toIso8601String().substring(0, 10)}'
        GROUP BY u.id 
        HAVING xp > 0
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

  Future<List<Map<String, dynamic>>> getGlobalRanking() async {
    try {
      final minWait = Future.delayed(const Duration(milliseconds: 400));
      final queryJob = _client.query('''
        SELECT id, username, name, xp, country, is_pro FROM users 
        WHERE xp > 0
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

      final safeUsername = newUsername.replaceAll("'", "''");
      final dupCheck = await _client.query(
        "SELECT id FROM users WHERE username = '$safeUsername' AND id != '$userId'",
      );
      if (dupCheck.isNotEmpty) return 'El nombre de usuario ya está en uso.';

      final now = DateTime.now().toIso8601String();
      await _client.execute(
        "UPDATE users SET username = '$safeUsername', last_username_update = '$now' WHERE id = '$userId'",
      );
      return null;
    } catch (e) {
      print('Exception updateUsername: $e');
      return 'Error al actualizar el nombre de usuario.';
    }
  }

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

  Future<List<String>> getTechnologies() async {
    return [
      'Dart',
      'Flutter',
      'SQL',
      'Python',
      'JavaScript',
      'PHP',
      'Rust',
      'Java',
      'Kotlin',
      'Swift',
      'C++',
      'Go',
      'Linux',
      'HTML',
      'CSS',
    ];
  }

  Future<void> migrateGuestData(String guestId, String realUserId) async {
    try {
      print('🔄 Migrando datos de $guestId a $realUserId...');

      final guestData = await _client.query(
        "SELECT xp, current_streak FROM users WHERE id = '$guestId'",
      );

      if (guestData.isNotEmpty) {
        final guestXp = guestData.first['xp'] as int? ?? 0;
        final guestStreak = guestData.first['current_streak'] as int? ?? 0;

        await _client.execute('''
          UPDATE users SET 
            xp = xp + $guestXp,
            current_streak = CASE WHEN $guestStreak > current_streak THEN $guestStreak ELSE current_streak END
          WHERE id = '$realUserId'
        ''');
        print('✅ XP y Racha migrados.');
      }

      await _client.execute('''
        UPDATE user_sessions SET user_id = '$realUserId' WHERE user_id = '$guestId'
      ''');
      print('✅ Sesiones de reto vinculadas.');
      await _client.execute("DELETE FROM users WHERE id = '$guestId'");
      print('✅ Registro de invitado eliminado.');
    } catch (e) {
      print('❌ Error en migrateGuestData: $e');
      rethrow;
    }
  }

  Future<bool> canUserPlayChallenge(String userId) async {
    try {
      final userSet = await _client.query(
        "SELECT is_pro, reward_tickets FROM users WHERE id = '$userId'",
      );
      if (userSet.isEmpty) return true;

      final isPro = userSet.first['is_pro'] == 1;
      final ticketsVal = userSet.first['reward_tickets'];
      final tickets = ticketsVal is BigInt
          ? ticketsVal.toInt()
          : (ticketsVal as int? ?? 0);

      if (isPro) return true;
      if (tickets > 0) return true;

      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final countSet = await _client.query('''
        SELECT COUNT(*) as count FROM user_sessions 
        WHERE user_id = '$userId' 
          AND completion_date >= '$todayStr'
          AND is_practice = 1
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

  Future<void> grantAdRewardTicket(String userId) async {
    try {
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

  Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      final resultSet = await _client.query('''
        SELECT 
            COUNT(*) as total_played,
            COUNT(CASE WHEN is_success = 1 THEN 1 END) as total_won,
            MIN(CASE WHEN is_success = 1 THEN time_taken_seconds END) as best_time
        FROM user_sessions us
        WHERE us.user_id = '$userId'
        AND us.is_practice = 0
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
      final minWait = Future.delayed(const Duration(milliseconds: 400));

      final queryJob = _client.query('''
        SELECT * FROM challenges 
        WHERE technology = '$technology' 
          AND level = '$level'
          AND id NOT IN (SELECT challenge_id FROM user_sessions WHERE user_id = '$userId' AND is_success = 1)
          AND id NOT IN (SELECT challenge_id FROM daily_challenges)
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

      print(
        '⏳ Reto de $technology - $level no encontrado. Solicitando a las APIs de IA...',
      );
      final aiGenerated = await aiService.generateChallenge(technology, level);

      if (aiGenerated == null) return null;

      final newId = 'c_${DateTime.now().millisecondsSinceEpoch}';

      final t = aiGenerated['title'].toString().replaceAll("'", "''");
      final q = aiGenerated['question'].toString().replaceAll("'", "''");
      final c = aiGenerated['code_snippet'].toString().replaceAll("'", "''");
      final a = aiGenerated['correct_answer'].toString().replaceAll("'", "''");

      await _client.execute('''
        INSERT INTO challenges (id, title, question, code_snippet, correct_answer, technology, level, is_ai, creator_id)
        VALUES (
          '$newId', 
          '$t', 
          '$q', 
          '$c', 
          '$a', 
          '$technology', 
          '$level', 
          1,
          '$userId'
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

  Future<List<Map<String, dynamic>>> getUserSessions(
    String userId, {
    bool? onlyDaily,
    int limit = 20,
  }) async {
    try {
      String filterClause = "";
      if (onlyDaily == true) {
        filterClause = "AND is_practice = 0";
      } else if (onlyDaily == false) {
        filterClause = "AND is_practice = 1";
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

  Future<void> _seedInitialChallenges() async {
    try {
      final countSet = await _client.query(
        'SELECT COUNT(*) as total FROM challenges',
      );

      final total =
          int.tryParse(countSet.first['total']?.toString() ?? '0') ?? 0;
      if (total > 5) return;

      print('🌱 Sembrando retos profesionales iniciales...');

      final values = seedChallengesData
          .map((c) {
            escape(String key) =>
                (c[key]?.toString() ?? '').replaceAll("'", "''");
            return "('${escape('id')}', '${escape('title')}', "
                "'${escape('question')}', '${escape('code_snippet')}', "
                "'${escape('correct_answer')}', '${escape('technology')}', "
                "'${escape('level')}', 0, NULL)";
          })
          .join(',\n');

      if (values.isNotEmpty) {
        await _client.execute('''
          INSERT OR REPLACE INTO challenges
            (id, title, question, code_snippet, correct_answer, technology, level, is_ai, creator_id)
          VALUES $values
        ''');
      }

      print('✅ ${seedChallengesData.length} retos semilla cargados en batch.');
    } catch (e) {
      print('❌ Error en _seedInitialChallenges: $e');
    }
  }

  /// Obtiene el progreso de los últimos 7 días (para el calendario de racha)
  Future<List<int>> getWeeklyProgress(String userId) async {
    try {
      final now = DateTime.now();
      final sevenDaysAgo = DateTime(now.year, now.month, now.day - 7);
      final sevenDaysAgoStr = sevenDaysAgo.toIso8601String().substring(0, 10);

      final resultSet = await _client.query('''
        SELECT completion_date, MAX(is_success) as status
        FROM user_sessions 
        WHERE user_id = '$userId' 
        AND completion_date >= '$sevenDaysAgoStr'
        AND is_practice = 0
        GROUP BY completion_date
      ''');

      final Map<String, int> dateStatus = {
        for (var row in resultSet)
          row['completion_date'].toString(): _toInt(row['status']),
      };

      final List<int> progress = [];
      for (int i = 0; i < 7; i++) {
        final day = DateTime(now.year, now.month, now.day - i);
        // Padding with 0s ensures YYYY-MM-DD
        final dayStr =
            "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
        progress.add(dateStatus[dayStr] ?? 0);
      }

      return progress;
    } catch (e) {
      print('Exception getWeeklyProgress: $e');
      return List.filled(7, 0);
    }
  }

  /// Limpia TODAS las tablas para iniciar en blanco. Úsalo con cuidado.
  Future<void> clearAllData() async {
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
      final sevenDaysAgo = DateTime(now.year, now.month, now.day - 6);
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
        final day = DateTime(now.year, now.month, now.day - i);
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
