// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admob_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(adMobService)
final adMobServiceProvider = AdMobServiceProvider._();

final class AdMobServiceProvider
    extends $FunctionalProvider<AdMobService, AdMobService, AdMobService>
    with $Provider<AdMobService> {
  AdMobServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'adMobServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$adMobServiceHash();

  @$internal
  @override
  $ProviderElement<AdMobService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AdMobService create(Ref ref) {
    return adMobService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AdMobService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AdMobService>(value),
    );
  }
}

String _$adMobServiceHash() => r'134dc896e2d5eefda6a550ef8c1c5840c266a341';
