import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dyktowanie i komendy glosowe.
///
/// Rozpoznawanie mowy uruchamiamy przez aplikacje systemowa
/// (`RecognizerIntent`), wiec aplikacja NIE potrzebuje uprawnienia
/// RECORD_AUDIO — nagrywaniem zajmuje sie system.
class VoiceService {
  static const _channel = MethodChannel('kolekcja/voice');

  /// Czy na urzadzeniu jest aplikacja do dyktowania.
  static Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _channel.invokeMethod<bool>('isSpeechAvailable') ?? false;
    } catch (e) {
      debugPrint('VoiceService.isAvailable: $e');
      return false;
    }
  }

  /// Otwiera systemowe okno dyktowania. Zwraca rozpoznany tekst
  /// lub null gdy uzytkownik anulowal / nic nie rozpoznano.
  static Future<String?> listen({String? localeCode}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>(
        'recognizeSpeech',
        {'locale': localeCode},
      );
    } catch (e) {
      debugPrint('VoiceService.listen: $e');
      return null;
    }
  }

  /// Fraza przekazana przez Asystenta Google ("zagraj ... w Kolekcja Muzyki").
  /// Zwraca ja tylko raz — kolejne wywolanie da null, dopoki nie przyjdzie
  /// nowa komenda. Pusty string = "wlacz muzyke" bez konkretnej frazy.
  static Future<String?> consumePendingSearch() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _channel.invokeMethod<String>('consumePendingSearch');
    } catch (e) {
      debugPrint('VoiceService.consumePendingSearch: $e');
      return null;
    }
  }
}
