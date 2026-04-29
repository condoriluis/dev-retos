import '../config/admob_config.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'admob_service.g.dart';

class AdMobService {
  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isAdLoading = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  String _lastErrorMessage = 'Sin errores';
  int _lastErrorCode = -1;

  final String _adUnitId = AdMobConfig.rewardedAdUnitId;

  void init() {
    // Pequeño retraso para asegurar que el SDK esté 100% sincronizado con la red
    Future.delayed(const Duration(seconds: 2), () {
      loadRewardedAd();
    });
  }

  void loadRewardedAd() {
    if (_isAdLoaded || _isAdLoading) return;

    _isAdLoading = true;
    print('💸 Intentando cargar anuncio (Unidad: $_adUnitId)...');

    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          _isAdLoading = false;
          _retryCount = 0; // Resetear contador al éxito
          print('✅ Ad Cargado exitosamente y listo en memoria.');
        },
        onAdFailedToLoad: (LoadAdError error) {
          print(
            '❌ Falló la carga del Ad: ${error.message} (Código: ${error.code})',
          );
          _lastErrorMessage = error.message;
          _lastErrorCode = error.code;
          _isAdLoaded = false;
          _isAdLoading = false;
          _rewardedAd = null;

          // Lógica de Reintento Automático
          if (_retryCount < _maxRetries) {
            _retryCount++;
            final delaySeconds = 15 * _retryCount;
            print(
              '⏳ Reintentando carga en $delaySeconds segundos... (Intento $_retryCount/$_maxRetries)',
            );
            Future.delayed(
              Duration(seconds: delaySeconds),
              () => loadRewardedAd(),
            );
          } else {
            print('🚫 Se agotaron los reintentos de carga para esta sesión.');
          }
        },
      ),
    );
  }

  bool showRewardedAd({
    required Function() onRewardEarned,
    required Function() onAdClosed,
  }) {
    if (!_isAdLoaded || _rewardedAd == null) {
      print('⚠️ El anuncio no estaba cargado. Intentando carga urgente...');
      loadRewardedAd();
      return false;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        loadRewardedAd();
        onAdClosed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        print('❌ Error al mostrar el Ad: ${error.message} (Código: ${error.code})');
        _lastErrorMessage = error.message;
        _lastErrorCode = error.code;
        ad.dispose();
        loadRewardedAd();
        onAdClosed();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        print(
          '🏆 ¡El usuario terminó de ver el video exitosamente! Otorgando recompensa.',
        );
        onRewardEarned();
      },
    );

    _rewardedAd = null;
    _isAdLoaded = false;
    _isAdLoading = false;
    return true;
  }

  bool get isAdLoaded => _isAdLoaded;
  bool get isAdLoading => _isAdLoading;
  String get lastErrorMessage => _lastErrorMessage;
  int get lastErrorCode => _lastErrorCode;
}

@riverpod
AdMobService adMobService(Ref ref) {
  final service = AdMobService();
  service.init();
  return service;
}
