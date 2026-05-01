import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init({void Function(String?)? onPayload}) async {
    tz.initializeTimeZones();
    try {
      String timeZoneName = await FlutterTimezone.getLocalTimezone();

      if (timeZoneName == 'GMT' || timeZoneName == 'UTC') {
        final duration = DateTime.now().timeZoneOffset;
        final hours = duration.inHours;

        final etcGmtName = "Etc/GMT${hours >= 0 ? '-' : '+'}${hours.abs()}";
        try {
          tz.setLocalLocation(tz.getLocation(etcGmtName));
          print('🔔 NotificationService: Fallback a zona horaria $etcGmtName');
        } catch (_) {
          tz.setLocalLocation(tz.getLocation('UTC'));
        }
      } else {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        print(
          '🔔 NotificationService: Zona horaria establecida a $timeZoneName',
        );
      }
    } catch (e) {
      print('🔔 NotificationService: Error al establecer zona horaria: $e');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsIOS,
        );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (response) {
        if (onPayload != null) {
          onPayload(response.payload);
        }
      },
    );

    print('🔔 NotificationService: Inicializado correctamente.');
  }

  Future<bool> requestPermissions() async {
    print('🔔 NotificationService: Solicitando permisos...');

    bool result = false;
    bool iosResult = false;

    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      result = await androidPlugin?.requestNotificationsPermission() ?? false;

      try {
        final bool? exactAlarmResult = await androidPlugin
            ?.requestExactAlarmsPermission();
        print(
          '🔔 NotificationService: Permiso de alarma exacta: $exactAlarmResult',
        );
      } catch (e) {
        print('🔔 NotificationService: Error al solicitar alarma exacta: $e');
      }
    } else if (Platform.isIOS) {
      iosResult =
          await _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }

    return result || iosResult;
  }

  Future<void> scheduleDailyReminder(int currentStreak) async {
    print(
      '🔔 NotificationService: Programando recordatorio (Racha: $currentStreak) para las 9:00 AM...',
    );

    final titleHtml = currentStreak > 0
        ? '<b>¡Reto Diario Listo!</b>'
        : '<b>¡Reto Diario Listo!</b>';

    final bodyHtml = currentStreak > 0
        ? 'Llevas <b>$currentStreak días</b> de racha. ¡No la rompas! Entra ahora y demuestra tu instinto de código.'
        : 'Es el momento perfecto para empezar una nueva racha. ¡Entra ahora y resuelve el desafío!';

    final plainTitle = currentStreak > 0
        ? '¡Reto Diario Listo! '
        : '¡Reto Diario Listo! ';
    final plainBody = currentStreak > 0
        ? 'Llevas $currentStreak días de racha. ¡No la rompas!'
        : 'Es el momento perfecto para empezar una nueva racha.';

    await _notificationsPlugin.zonedSchedule(
      id: 100,
      title: plainTitle,
      body: plainBody,
      scheduledDate: _nextInstanceOfTime(9, 0),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_retos_channel',
          'Recordatorios Diarios',
          channelDescription: 'Canal para recordatorios de retos diarios',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          color: const Color(0xFF00E676),
          ledColor: const Color(0xFF00E676),
          ledOnMs: 1000,
          ledOffMs: 500,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(
            bodyHtml,
            htmlFormatBigText: true,
            contentTitle: titleHtml,
            htmlFormatContentTitle: true,
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: '/diario',
    );
  }

  Future<void> scheduleTestNotification() async {
    print(
      '🔔 NotificationService: Programando notificación de prueba en 5 segundos...',
    );

    final now = tz.TZDateTime.now(tz.local);
    final testTime = now.add(const Duration(seconds: 5));

    await _notificationsPlugin.zonedSchedule(
      id: 999,
      title: '🧪 Prueba de Notificación',
      body:
          '¡Funciona! Si ves esto, las notificaciones están operativas en tu dispositivo.',
      scheduledDate: testTime,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'test_channel',
          'Pruebas de Sistema',
          channelDescription: 'Canal para verificar notificaciones',
          importance: Importance.max,
          priority: Priority.high,
          color: Color(0xFF00E676),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> showInstantNotification({
    required String title,
    required String body,
  }) async {
    print('🔔 NotificationService: Enviando notificación instantánea...');

    await _notificationsPlugin.show(
      id: 99,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'instant_retos_channel',
          'Notificaciones Inmediatas',
          channelDescription: 'Canal para alertas inmediatas y bienvenida',
          importance: Importance.max,
          priority: Priority.high,
          color: Color(0xFF00E676),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: '/diario',
    );
  }

  Future<void> cancelAllNotifications() async {
    print('🔔 NotificationService: Cancelando todas las notificaciones.');
    await _notificationsPlugin.cancelAll();
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
