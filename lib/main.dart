import 'package:flutter/widgets.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import 'app.dart';
import 'storage/host_info.dart';
import 'storage/paired_host_store.dart';
import 'storage/settings_store.dart';
import 'transport/bluetooth_discovery.dart';
import 'transport/bluetooth_transport_client.dart';
import 'transport/transport_manager.dart';
import 'transport/wifi_discovery.dart';
import 'transport/wifi_transport_client.dart';
import 'ui/host_list_screen.dart';

export 'app.dart' show MyApp, AppDependencies;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsStore.load();
  final manager = TransportManager(
    clientFactory: (kind) => kind == TransportKind.wifi
        ? WifiTransportClient()
        : BluetoothTransportClient(),
    pairedHosts: PairedHostStore(),
  );
  runApp(
    MyApp(
      dependencies: AppDependencies(
        manager: manager,
        settings: settings,
        discoveries: [const WifiDiscovery(), BluetoothDiscovery()],
        permissionRequester: const PermissionHandlerRequester(),
        onTurnOnBluetooth: () async {
          await FlutterBlueClassic().turnOn();
        },
      ),
    ),
  );
}
