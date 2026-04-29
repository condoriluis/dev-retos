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
    // Configurar la zona horaria local
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      print('🔔 NotificationService: Zona horaria establecida a $timeZoneName');
    } catch (e) {
      print('🔔 NotificationService: Error al establecer zona horaria: $e');
      // Si falla, intentamos usar UTC como fallback o dejar tz.local por defecto
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

      // Permiso de notificaciones (Android 13+)
      result = await androidPlugin?.requestNotificationsPermission() ?? false;

      // Permiso de alarmas exactas (Crucial para Android 14+)
      // Nota: Esto puede abrir una pantalla de configuración del sistema si es necesario
      try {
        final bool? exactAlarmResult =
            await androidPlugin?.requestExactAlarmsPermission();
        print('🔔 NotificationService: Permiso de alarma exacta: $exactAlarmResult');
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
      id: 100, // ID único para el recordatorio diario
      title: plainTitle,
      body: plainBody,
      scheduledDate: _nextInstanceOfTime(9, 0), // 9:00 AM (producción)
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_retos_channel',
          'Recordatorios Diarios',
          channelDescription: 'Canal para recordatorios de retos diarios',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          color: const Color(0xFF00E676), // Verde neón profesional
          ledColor: const Color(0xFF00E676),
          ledOnMs: 1000,
          ledOffMs: 500,
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
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload:
          '/diario', // Payload para saber a dónde ir al tocar la notificación
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
