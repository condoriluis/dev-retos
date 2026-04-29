import 'package:flutter/foundation.dart';

class AdMobConfig {
  /// App ID real de tu consola AdMob (Android)
  static const String appIdAndroid = 'ca-app-pub-2175792751809653~5380895787';

  /// Unidad de Anuncio Recompensado real
  static const String rewardedAdUnitIdAndroid = 'ca-app-pub-2175792751809653/3920474458';

  // IDs de Prueba Oficiales de Google (Para desarrollo)
  static const String testRewardedAdUnitIdAndroid = 'ca-app-pub-3940256099942544/5224354917';

  /// Retorna el ID de la unidad dependiendo de si estamos en Debug o Release
  static String get rewardedAdUnitId {
    if (kDebugMode) {
      return testRewardedAdUnitIdAndroid; // Siempre probar con IDs de test para evitar baneos
    }
    return rewardedAdUnitIdAndroid; // Usar Real solo al generar el APK para subir a la tienda
  }
}
