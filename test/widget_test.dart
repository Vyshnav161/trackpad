import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackpad/main.dart';
import 'package:trackpad/storage/host_info.dart';
import 'package:trackpad/storage/paired_host_store.dart';
import 'package:trackpad/storage/settings_store.dart';
import 'package:trackpad/transport/transport_client.dart';
import 'package:trackpad/transport/transport_manager.dart';
import 'package:trackpad/ui/host_list_screen.dart';

class _NoPermissions implements PermissionRequester {
  @override
  Future<Set<DiscoveryPermission>> missing() async => {};
  @override
  Future<Set<DiscoveryPermission>> request(
          Set<DiscoveryPermission> permissions) async =>
      {};
}

class _UnusedClient implements TransportClient {
  @override
  TransportKind get kind => TransportKind.wifi;
  @override
  Stream<Uint8List> get frames => const Stream.empty();
  @override
  Stream<void> get onClosed => const Stream.empty();
  @override
  Future<void> connect(HostInfo host) async {}
  @override
  Future<void> send(Uint8List frameBody) async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('App builds and shows the host list', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    final manager = TransportManager(
      clientFactory: (_) => _UnusedClient(),
      pairedHosts: PairedHostStore(),
    );

    await tester.pumpWidget(MyApp(
      dependencies: AppDependencies(
        manager: manager,
        settings: settings,
        discoveries: const [],
        permissionRequester: _NoPermissions(),
      ),
    ));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.byType(HostListScreen), findsOneWidget);

    // Let the no-host timer finish.
    await tester.pump(const Duration(seconds: 11));
    expect(find.byKey(const Key('no-host-message')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await manager.dispose();
  });
}
