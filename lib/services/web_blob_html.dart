// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Tworzy blob URL z bajtow pliku — pozwala odtwarzaczowi HTML5 grac plik
/// wybrany z dysku w przegladarce. URL zyje do zamkniecia karty.
String createBlobUrl(List<int> bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}
