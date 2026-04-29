// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_challenge_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(aiChallengeService)
final aiChallengeServiceProvider = AiChallengeServiceProvider._();

final class AiChallengeServiceProvider
    extends
        $FunctionalProvider<
          AiChallengeService,
          AiChallengeService,
          AiChallengeService
        >
    with $Provider<AiChallengeService> {
  AiChallengeServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiChallengeServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiChallengeServiceHash();

  @$internal
  @override
  $ProviderElement<AiChallengeService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AiChallengeService create(Ref ref) {
    return aiChallengeService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiChallengeService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiChallengeService>(value),
    );
  }
}

String _$aiChallengeServiceHash() =>
    r'4f323dfd05c027c8866b262c4eddfdae09e0646c';
