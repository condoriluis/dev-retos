// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'turso_client.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(tursoClient)
final tursoClientProvider = TursoClientProvider._();

final class TursoClientProvider
    extends $FunctionalProvider<LibsqlClient, LibsqlClient, LibsqlClient>
    with $Provider<LibsqlClient> {
  TursoClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tursoClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tursoClientHash();

  @$internal
  @override
  $ProviderElement<LibsqlClient> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LibsqlClient create(Ref ref) {
    return tursoClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibsqlClient value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibsqlClient>(value),
    );
  }
}

String _$tursoClientHash() => r'dfb69cb9efb93d1d430e193d8b9a8164776d043b';
