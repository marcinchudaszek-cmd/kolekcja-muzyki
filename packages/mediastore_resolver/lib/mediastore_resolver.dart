import 'package:flutter/services.dart';

/// Zamiana surowej sciezki pliku audio na content:// URI z MediaStore.
///
/// Kanal jest rejestrowany jako plugin, a nie w MainActivity, bo Android Auto
/// potrafi uruchomic aplikacje bez Activity (sam serwis multimediow). Kanal
/// z MainActivity nie istnial wtedy w ogole, a odtwarzanie po surowej
/// sciezce konczy sie na Androidzie 13+ bledem EACCES.
class MediastoreResolver {
  static const MethodChannel _channel =
      MethodChannel('beagleapps/mediastore_resolver');

  static Future<String?> uriForPath(String path) =>
      _channel.invokeMethod<String>('uriForPath', {'path': path});
}
