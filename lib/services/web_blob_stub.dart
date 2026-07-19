/// Stub dla platform innych niz web. Uzywany przez conditional import w
/// scan_folder_screen.dart — na Androidzie/iOS ta funkcja nie jest wywolywana.
String createBlobUrl(List<int> bytes, String mimeType) {
  throw UnsupportedError('createBlobUrl jest dostepne tylko na web');
}
