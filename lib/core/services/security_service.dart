import 'package:screen_protector/screen_protector.dart';

/// Service to handle security-related window flags, such as blocking screenshots.
/// Using the modern screen_protector package for cross-platform support.
class SecurityService {
  /// Enables or disables screenshot protection (Android and iOS).
  /// 
  /// When [enable] is true, screenshots and screen recordings will be blocked.
  /// When [enable] is false, the protection is removed.
  static Future<void> setSecureMode(bool enable) async {
    try {
      if (enable) {
        // En Android activa FLAG_SECURE
        // En iOS activa la detección y máscara de grabación/captura
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.preventScreenshotOn(); // Se llama dos veces para asegurar grabación en algunos casos
      } else {
        await ScreenProtector.preventScreenshotOff();
      }
    } catch (e) {
      // Log error but don't crash the app if security flag fails.
      print('SecurityService error: $e');
    }
  }
}
