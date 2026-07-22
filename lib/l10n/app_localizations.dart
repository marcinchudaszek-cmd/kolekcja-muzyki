import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Obslugiwane jezyki aplikacji.
enum AppLang {
  pl('Polski', 'pl'),
  en('English', 'en'),
  de('Deutsch', 'de');

  const AppLang(this.label, this.code);

  final String label;
  final String code;

  Locale get locale => Locale(code);

  static AppLang fromCode(String? code) => AppLang.values
      .firstWhere((l) => l.code == code, orElse: () => AppLang.pl);
}

/// Przechowuje wybrany jezyk i zapamietuje go miedzy uruchomieniami.
class LocaleProvider extends ChangeNotifier {
  static const _prefsKey = 'app_language';

  AppLang _lang = AppLang.pl;
  AppLang get lang => _lang;
  Locale get locale => _lang.locale;
  L get l => L(_lang);

  /// Wczytaj zapisany jezyk (wywolaj przed runApp).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _lang = AppLang.fromCode(prefs.getString(_prefsKey));
  }

  Future<void> setLang(AppLang lang) async {
    if (lang == _lang) return;
    _lang = lang;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, lang.code);
  }
}

/// Teksty aplikacji. Kazdy getter zwraca wersje w aktualnym jezyku.
/// Dodajac nowy tekst: `String get x => _t('polski', 'english', 'deutsch');`
class L {
  const L(this.lang);

  final AppLang lang;

  /// Pobiera teksty i przebudowuje widget przy zmianie jezyka (uzywaj w build).
  static L of(BuildContext context) =>
      Provider.of<LocaleProvider>(context).l;

  /// Wersja bez nasluchiwania — do uzycia w callbackach (np. po await).
  static L read(BuildContext context) =>
      Provider.of<LocaleProvider>(context, listen: false).l;

  String _t(String pl, String en, String de) => switch (lang) {
        AppLang.pl => pl,
        AppLang.en => en,
        AppLang.de => de,
      };

  // ===================== Wspolne =====================
  String get appTitle => _t('Kolekcja Muzyki', 'Music Collection', 'Musiksammlung');
  String get cancel => _t('Anuluj', 'Cancel', 'Abbrechen');
  String get save => _t('Zapisz', 'Save', 'Speichern');
  String get delete => _t('Usun', 'Delete', 'Löschen');
  String get edit => _t('Edytuj', 'Edit', 'Bearbeiten');
  String get add => _t('Dodaj', 'Add', 'Hinzufügen');
  String get ok => _t('OK', 'OK', 'OK');
  String get yes => _t('Tak', 'Yes', 'Ja');
  String get no => _t('Nie', 'No', 'Nein');
  String get close => _t('Zamknij', 'Close', 'Schließen');
  String get retry => _t('Ponów', 'Retry', 'Wiederholen');
  String get search => _t('Szukaj', 'Search', 'Suchen');
  String get unknownArtist => _t('Nieznany artysta', 'Unknown artist', 'Unbekannter Künstler');
  String get unknownAlbum => _t('Nieznany album', 'Unknown album', 'Unbekanntes Album');

  // ===================== Ustawienia jezyka =====================
  String get language => _t('Język', 'Language', 'Sprache');
  String get languageSubtitle =>
      _t('Wybierz język aplikacji', 'Choose app language', 'App-Sprache wählen');

  // ===================== Ekran Ustawien =====================
  String get settings => _t('Ustawienia', 'Settings', 'Einstellungen');
  String get sectionCovers => _t('Okładki', 'Covers', 'Cover');
  String get sectionPlayer => _t('Odtwarzacz', 'Player', 'Player');
  String get sectionData => _t('Dane', 'Data', 'Daten');
  String get sectionAbout => _t('Informacje', 'About', 'Info');
  String get sectionAppearance => _t('Wygląd', 'Appearance', 'Darstellung');
  String get downloadCovers =>
      _t('Pobierz brakujące okładki', 'Download missing covers', 'Fehlende Cover laden');
  String get downloadCoversSubtitle => _t('Pobierz okładki dla wszystkich albumów',
      'Download covers for all albums', 'Cover für alle Alben laden');
  String downloadingCovers(int done, int total) => _t(
      'Pobieranie... $done/$total', 'Downloading... $done/$total', 'Laden... $done/$total');
  String coversDownloaded(int count) => _t('Pobrano okładki dla $count albumów',
      'Downloaded covers for $count albums', 'Cover für $count Alben geladen');
  String get coversTitle => _t('Okładki', 'Covers', 'Cover');
  String get allHaveCovers => _t('Wszystkie albumy mają już okładki!',
      'All albums already have covers!', 'Alle Alben haben bereits Cover!');
  String get audioSettings => _t('Ustawienia dźwięku', 'Audio settings', 'Audio-Einstellungen');
  String get audioSettingsSubtitle =>
      _t('Equalizer, crossfade', 'Equalizer, crossfade', 'Equalizer, Crossfade');
  String get listeningHistory =>
      _t('Historia słuchania', 'Listening history', 'Wiedergabeverlauf');
  String get listeningHistorySubtitle => _t('Ostatnio odtwarzane, statystyki',
      'Recently played, statistics', 'Zuletzt gespielt, Statistiken');
  String get recognizeSong => _t('Rozpoznaj utwór', 'Recognize song', 'Song erkennen');
  String get recognizeSongSubtitle =>
      _t('Znajdź piosenkę po dźwięku', 'Find a song by sound', 'Song per Ton finden');
  String get exportCollection =>
      _t('Eksportuj kolekcję', 'Export collection', 'Sammlung exportieren');
  String get exportCollectionSubtitle => _t('Zapisz kopię zapasową jako JSON',
      'Save a backup as JSON', 'Backup als JSON speichern');
  String get importCollection =>
      _t('Importuj kolekcję', 'Import collection', 'Sammlung importieren');
  String get importCollectionSubtitle =>
      _t('Wczytaj z pliku JSON', 'Load from a JSON file', 'Aus JSON-Datei laden');
  String get clearCollection =>
      _t('Wyczyść kolekcję', 'Clear collection', 'Sammlung löschen');
  String get clearCollectionSubtitle =>
      _t('Usuń wszystkie albumy', 'Delete all albums', 'Alle Alben löschen');
  String get clearCollectionConfirm => _t(
      'Ta operacja usunie wszystkie albumy. Czy na pewno chcesz kontynuować?',
      'This will delete all albums. Are you sure you want to continue?',
      'Dies löscht alle Alben. Möchtest du wirklich fortfahren?');
  String get collectionCleared =>
      _t('Kolekcja wyczyszczona', 'Collection cleared', 'Sammlung gelöscht');
  String savedTo(String path) => _t('Zapisano: $path', 'Saved: $path', 'Gespeichert: $path');
  String exportError(Object e) => _t('Błąd eksportu: $e', 'Export error: $e', 'Exportfehler: $e');
  String importError(Object e) => _t('Błąd importu: $e', 'Import error: $e', 'Importfehler: $e');
  String importedAlbums(int count) => _t('Zaimportowano $count albumów',
      'Imported $count albums', '$count Alben importiert');
  // ===================== Ekran glowny =====================
  String get myCollection => _t('🎵 Moja Kolekcja', '🎵 My Collection', '🎵 Meine Sammlung');
  String get searchAlbums =>
      _t('Szukaj albumów...', 'Search albums...', 'Alben suchen...');
  String get viewList => _t('Widok listy', 'List view', 'Listenansicht');
  String get viewGrid => _t('Widok kafelków', 'Grid view', 'Kachelansicht');
  String get statistics => _t('Statystyki', 'Statistics', 'Statistiken');
  String get labelAlbums => _t('albumów', 'albums', 'Alben');
  String get labelTracks => _t('utworów', 'tracks', 'Titel');
  String get labelFavorites => _t('ulubionych', 'favorites', 'Favoriten');
  String get filterAll => _t('Wszystkie', 'All', 'Alle');
  String get wishlist => _t('Lista życzeń', 'Wishlist', 'Wunschliste');
  String get clearShort => _t('Wyczyść', 'Clear', 'Löschen');
  String get emptyCollection =>
      _t('Twoja kolekcja jest pusta', 'Your collection is empty', 'Deine Sammlung ist leer');
  String get addAlbumsToCollection => _t('Dodaj albumy do swojej kolekcji',
      'Add albums to your collection', 'Füge Alben zu deiner Sammlung hinzu');
  String get addOrScan => _t('Dodaj albumy lub zeskanuj muzykę z telefonu',
      'Add albums or scan music from your phone', 'Alben hinzufügen oder Musik vom Telefon scannen');
  String get addAlbum => _t('Dodaj album', 'Add album', 'Album hinzufügen');
  String get scanFromPhone => _t('Skanuj muzykę z telefonu',
      'Scan music from phone', 'Musik vom Telefon scannen');
  String get scanFromPhoneSub => _t('Znajdź albumy w pamięci urządzenia',
      'Find albums in device storage', 'Alben im Gerätespeicher finden');
  String get scanBarcode =>
      _t('Skanuj kod kreskowy', 'Scan barcode', 'Barcode scannen');
  String get scanBarcodeSub => _t('Zeskanuj kod z płyty CD lub winyla',
      'Scan a CD or vinyl barcode', 'CD- oder Vinyl-Barcode scannen');
  String get addManually => _t('Dodaj ręcznie', 'Add manually', 'Manuell hinzufügen');
  String get addManuallySub =>
      _t('Wpisz dane albumu', 'Enter album details', 'Albumdaten eingeben');
  String tracksCount(int n) => _t('$n utworów', '$n tracks', '$n Titel');
  String get sort => _t('Sortuj', 'Sort', 'Sortieren');
  String get sortBy => _t('Sortuj według', 'Sort by', 'Sortieren nach');
  String get sortArtist => _t('Artysta', 'Artist', 'Künstler');
  String get sortTitle => _t('Tytuł', 'Title', 'Titel');
  String get sortYear => _t('Rok', 'Year', 'Jahr');
  String get sortRating => _t('Ocena', 'Rating', 'Bewertung');
  String get sortRecent => _t('Ostatnio dodane', 'Recently added', 'Zuletzt hinzugefügt');
  String get sortRecentShort => _t('Ostatnie', 'Recent', 'Neueste');
  String get ascending => _t('Rosnąco', 'Ascending', 'Aufsteigend');
  String get descending => _t('Malejąco', 'Descending', 'Absteigend');
  String get genre => _t('Gatunek', 'Genre', 'Genre');
  String get format => _t('Format', 'Format', 'Format');
  String get formatVinyl => _t('Winyl', 'Vinyl', 'Vinyl');
  String get formatDigital => _t('Cyfrowy', 'Digital', 'Digital');
  String get formatCassette => _t('Kaseta', 'Cassette', 'Kassette');

  // ===================== Szczegoly albumu =====================
  String get albumNotFound => _t('Album nie znaleziony', 'Album not found', 'Album nicht gefunden');
  String get addToWishlist =>
      _t('Dodaj do listy życzeń', 'Add to wishlist', 'Zur Wunschliste hinzufügen');
  String get removeFromWishlist =>
      _t('Usuń z listy życzeń', 'Remove from wishlist', 'Von Wunschliste entfernen');
  String get ratingLabel => _t('Ocena: ', 'Rating: ', 'Bewertung: ');
  String get listenOnline => _t('Słuchaj online', 'Listen online', 'Online anhören');
  String get searchYouTube =>
      _t('Szukaj na YouTube', 'Search on YouTube', 'Auf YouTube suchen');
  String get playAlbum => _t('Odtwórz album', 'Play album', 'Album abspielen');
  String playbackError(Object e) =>
      _t('Błąd odtwarzania: $e', 'Playback error: $e', 'Wiedergabefehler: $e');
  String get trackList => _t('Lista utworów', 'Track list', 'Titelliste');
  String tracksAvailable(int available, int total) => _t(
      '$available/$total dostępnych', '$available/$total available', '$available/$total verfügbar');
  String get deleteAlbumTitle => _t('Usunąć album?', 'Delete album?', 'Album löschen?');
  String deleteAlbumConfirm(String title) => _t(
      'Czy na pewno chcesz usunąć „$title"?',
      'Are you sure you want to delete "$title"?',
      'Möchtest du „$title" wirklich löschen?');
  String get changeCover => _t('Zmień okładkę', 'Change cover', 'Cover ändern');
  String get searchAuto =>
      _t('Wyszukaj automatycznie', 'Search automatically', 'Automatisch suchen');
  String get searchAutoSub => _t('Pobierz okładkę z internetu',
      'Download cover from the internet', 'Cover aus dem Internet laden');
  String get chooseSuggestion =>
      _t('Wybierz z propozycji', 'Choose from suggestions', 'Aus Vorschlägen wählen');
  String get chooseSuggestionSub =>
      _t('Zobacz kilka opcji', 'See a few options', 'Einige Optionen ansehen');
  String get pasteUrl => _t('Wklej URL', 'Paste URL', 'URL einfügen');
  String get pasteUrlSub =>
      _t('Podaj adres obrazka', 'Enter image address', 'Bildadresse eingeben');
  String get removeCover => _t('Usuń okładkę', 'Remove cover', 'Cover entfernen');
  String get coverRemoved => _t('Okładka usunięta', 'Cover removed', 'Cover entfernt');
  String get searchingCover => _t('Szukam okładki...', 'Searching cover...', 'Suche Cover...');
  String get coverUpdated =>
      _t('Okładka zaktualizowana!', 'Cover updated!', 'Cover aktualisiert!');
  String get coverNotFound =>
      _t('Nie znaleziono okładki', 'Cover not found', 'Kein Cover gefunden');
  String errorGeneric(Object e) => _t('Błąd: $e', 'Error: $e', 'Fehler: $e');
  String get loadingSuggestions =>
      _t('Pobieram propozycje...', 'Loading suggestions...', 'Lade Vorschläge...');
  String get noSuggestions =>
      _t('Nie znaleziono propozycji', 'No suggestions found', 'Keine Vorschläge gefunden');
  String get chooseCover => _t('Wybierz okładkę', 'Choose cover', 'Cover wählen');
  String get coverChanged => _t('Okładka zmieniona!', 'Cover changed!', 'Cover geändert!');
  String get pasteCoverUrl =>
      _t('Wklej URL okładki', 'Paste cover URL', 'Cover-URL einfügen');

  // ===================== Odtwarzacz =====================
  String get noTrackPlaying =>
      _t('Brak odtwarzanego utworu', 'No track playing', 'Kein Titel wird abgespielt');
  String get playingFrom => _t('ODTWARZANE Z', 'PLAYING FROM', 'WIRD ABGESPIELT VON');
  String get queueShort => _t('Lista', 'Queue', 'Liste');
  String get goToAlbum => _t('Przejdź do albumu', 'Go to album', 'Zum Album');
  String get share => _t('Udostępnij', 'Share', 'Teilen');

  // ===================== Skanowanie muzyki / folderu =====================
  String get scanMusicTitle => _t('Skanuj muzykę', 'Scan music', 'Musik scannen');
  String get scanFolderTitle => _t('Skanuj folder', 'Scan folder', 'Ordner scannen');
  String get scanningMusic => _t('Skanowanie muzyki...', 'Scanning music...', 'Musik wird gescannt...');
  String get scanningFolder => _t('Skanuję folder...', 'Scanning folder...', 'Ordner wird gescannt...');
  String get selectFolder => _t('Wybierz folder z muzyką', 'Choose a music folder', 'Musikordner wählen');
  String get chooseFolder => _t('Wybierz folder', 'Choose folder', 'Ordner wählen');
  String foundAlbums(int count) =>
      _t('Znaleziono $count albumów', 'Found $count albums', '$count Alben gefunden');
  String get noAccessTitle =>
      _t('Brak dostępu do plików', 'No file access', 'Kein Dateizugriff');
  String get noAccessDesc => _t('Aplikacja potrzebuje dostępu do\nplików muzycznych na urządzeniu',
      'The app needs access to\nmusic files on your device', 'Die App benötigt Zugriff auf\nMusikdateien auf dem Gerät');
  String get grantAccess => _t('Udziel dostępu', 'Grant access', 'Zugriff gewähren');
  String get noMusicTitle => _t('Nie znaleziono muzyki', 'No music found', 'Keine Musik gefunden');
  String get noMusicDesc => _t('Nie znaleziono albumów w pamięci urządzenia',
      'No albums found in device storage', 'Keine Alben im Gerätespeicher gefunden');
  String get noAlbumsInFolder => _t('Nie znaleziono albumów w tym folderze',
      'No albums found in this folder', 'Keine Alben in diesem Ordner gefunden');
  String get scanAgain => _t('Skanuj ponownie', 'Scan again', 'Erneut scannen');
  String get selectAll => _t('Zaznacz wszystkie', 'Select all', 'Alle auswählen');
  String get deselectAll => _t('Odznacz wszystkie', 'Deselect all', 'Alle abwählen');
  String importCount(int count) => _t('Importuj ($count)', 'Import ($count)', 'Importieren ($count)');
  String importAlbumsCount(int count) =>
      _t('Importuj $count albumów', 'Import $count albums', '$count Alben importieren');
  String get selectAtLeastOne => _t('Wybierz przynajmniej jeden album',
      'Select at least one album', 'Wähle mindestens ein Album');
  String get importingAlbums => _t('Importowanie albumów...', 'Importing albums...', 'Alben werden importiert...');
  String get importing => _t('Importuję...', 'Importing...', 'Importiere...');
  String importingProgress(int i, int total, String album) => _t(
      'Importowanie $i/$total: $album', 'Importing $i/$total: $album', 'Importiere $i/$total: $album');
  String importedNew(int count) => _t('Zaimportowano $count nowych albumów',
      'Imported $count new albums', '$count neue Alben importiert');
  String importedNewWithSkipped(int imported, int skipped) => _t(
      'Zaimportowano $imported nowych albumów ($skipped pominięto - duplikaty)',
      'Imported $imported new albums ($skipped skipped - duplicates)',
      '$imported neue Alben importiert ($skipped übersprungen - Duplikate)');
  String importedOk(int imported, int skipped) => _t(
      '✅ Zaimportowano $imported albumów${skipped > 0 ? ' ($skipped pominięto)' : ''}',
      '✅ Imported $imported albums${skipped > 0 ? ' ($skipped skipped)' : ''}',
      '✅ $imported Alben importiert${skipped > 0 ? ' ($skipped übersprungen)' : ''}');
  String allExist(int skipped) => _t(
      '⚠️ Wszystkie wybrane albumy ($skipped) już istnieją w kolekcji',
      '⚠️ All selected albums ($skipped) already exist in the collection',
      '⚠️ Alle ausgewählten Alben ($skipped) sind bereits in der Sammlung');
  String get scanError => _t('Błąd skanowania', 'Scan error', 'Scan-Fehler');

  /// Podsumowanie importu z deduplikacja po plikach.
  String importSummary(int tracks, int albums, int skipped) {
    final pl = StringBuffer('Dodano $tracks utworów');
    final en = StringBuffer('Added $tracks tracks');
    final de = StringBuffer('$tracks Titel hinzugefügt');
    if (albums > 0) {
      pl.write(' w $albums nowych albumach');
      en.write(' in $albums new albums');
      de.write(' in $albums neuen Alben');
    }
    if (skipped > 0) {
      pl.write(', pominięto $skipped już istniejących');
      en.write(', skipped $skipped already in collection');
      de.write(', $skipped bereits vorhandene übersprungen');
    }
    return _t(pl.toString(), en.toString(), de.toString());
  }

  String get nothingNew => _t('Brak nowych utworów – wszystko już jest w kolekcji',
      'Nothing new – everything is already in your collection',
      'Nichts Neues – alles ist bereits in deiner Sammlung');

  // ===================== Usuwanie duplikatow =====================
  String get removeDuplicates =>
      _t('Usuń duplikaty', 'Remove duplicates', 'Duplikate entfernen');
  String get removeDuplicatesSub => _t('Scal powtórzone albumy i utwory',
      'Merge repeated albums and tracks', 'Doppelte Alben und Titel zusammenführen');
  String get removeDuplicatesConfirm => _t(
      'Aplikacja scali albumy o tej samej nazwie i usunie powtórzone utwory (ten sam plik). Pliki na dysku nie zostaną ruszone.',
      'Albums with the same name will be merged and repeated tracks (same file) removed. Files on disk are not touched.',
      'Alben mit gleichem Namen werden zusammengeführt und doppelte Titel (gleiche Datei) entfernt. Dateien auf dem Speicher bleiben unberührt.');
  String get searchingDuplicates =>
      _t('Szukam duplikatów...', 'Searching duplicates...', 'Suche Duplikate...');
  String duplicatesRemoved(int albums, int tracks) => _t(
      'Usunięto $albums zdublowanych albumów i $tracks utworów',
      'Removed $albums duplicate albums and $tracks tracks',
      '$albums doppelte Alben und $tracks Titel entfernt');
  String get noDuplicates =>
      _t('Nie znaleziono duplikatów', 'No duplicates found', 'Keine Duplikate gefunden');

  // ===================== Dodaj / edytuj album =====================
  String get addAlbumTitle => _t('Dodaj album', 'Add album', 'Album hinzufügen');
  String get editAlbumTitle => _t('Edytuj album', 'Edit album', 'Album bearbeiten');
  String get fieldArtist => _t('Artysta', 'Artist', 'Künstler');
  String get fieldTitle => _t('Tytuł', 'Title', 'Titel');
  String get fieldYear => _t('Rok', 'Year', 'Jahr');
  String get fieldGenre => _t('Gatunek', 'Genre', 'Genre');
  String get fieldFormat => _t('Format', 'Format', 'Format');
  String get fieldNotes => _t('Notatki', 'Notes', 'Notizen');
  String get fieldRequired => _t('To pole jest wymagane', 'This field is required', 'Dieses Feld ist erforderlich');
  String get albumSaved => _t('Album zapisany', 'Album saved', 'Album gespeichert');
  String get albumAdded => _t('Album dodany', 'Album added', 'Album hinzugefügt');
  String get albumTitleLabel => _t('Tytuł albumu', 'Album title', 'Albumtitel');
  String get releaseYear => _t('Rok wydania', 'Release year', 'Erscheinungsjahr');
  String get rating => _t('Ocena', 'Rating', 'Bewertung');
  String get notes => _t('Notatki', 'Notes', 'Notizen');
  String get saveAlbum => _t('Zapisz album', 'Save album', 'Album speichern');
  String get enterArtist => _t('Podaj artystę', 'Enter artist', 'Künstler eingeben');
  String get enterTitle => _t('Podaj tytuł', 'Enter title', 'Titel eingeben');
  String get albumExists =>
      _t('⚠️ Ten album już istnieje w kolekcji!', '⚠️ This album already exists in the collection!',
          '⚠️ Dieses Album ist bereits in der Sammlung!');
  String get downloadingCover =>
      _t('Pobieram okładkę...', 'Downloading cover...', 'Cover wird geladen...');
  String albumAddedMsg(bool withCover) => _t(
      '✅ Album dodany!${withCover ? ' (z okładką)' : ''}',
      '✅ Album added!${withCover ? ' (with cover)' : ''}',
      '✅ Album hinzugefügt!${withCover ? ' (mit Cover)' : ''}');
  String get albumUpdated => _t('Album zaktualizowany', 'Album updated', 'Album aktualisiert');
  String get saveChanges => _t('Zapisz zmiany', 'Save changes', 'Änderungen speichern');

  // ===================== Skaner kodow =====================
  String get orEnterCode =>
      _t('Lub wpisz kod ręcznie:', 'Or enter the code manually:', 'Oder Code manuell eingeben:');
  String get aimCamera => _t('Skieruj kamerę na kod kreskowy płyty',
      'Point the camera at the disc barcode', 'Kamera auf den Disc-Barcode richten');
  String get searchingMusicBrainz =>
      _t('Szukam w bazie MusicBrainz...', 'Searching MusicBrainz...', 'Suche in MusicBrainz...');
  String get untitled => _t('Bez tytułu', 'Untitled', 'Ohne Titel');
  String get albumFound => _t('Znaleziono album!', 'Album found!', 'Album gefunden!');
  String trackListCount(int n) =>
      _t('Lista utworów ($n)', 'Track list ($n)', 'Titelliste ($n)');
  String get scanAnother => _t('Skanuj inny', 'Scan another', 'Weiteren scannen');
  String get scanBarcodePrompt =>
      _t('Zeskanuj kod kreskowy', 'Scan a barcode', 'Barcode scannen');
  String get connectionError => _t('Błąd połączenia', 'Connection error', 'Verbindungsfehler');
  String noAlbumForCode(String code) => _t('Nie znaleziono albumu dla kodu: $code',
      'No album found for code: $code', 'Kein Album für Code gefunden: $code');
  String get errorFetchingDetails => _t('Błąd pobierania szczegółów',
      'Error fetching details', 'Fehler beim Abrufen der Details');
  String albumExistsNamed(String title) => _t(
      '⚠️ Album „$title" już istnieje w kolekcji!',
      '⚠️ Album "$title" already exists in the collection!',
      '⚠️ Album „$title" ist bereits in der Sammlung!');
  String codeLabel(String code) => _t('Kod: $code', 'Code: $code', 'Code: $code');
  String addedAlbum(String title, bool withCover) => _t(
      '✅ Dodano: $title${withCover ? ' (z okładką)' : ''}',
      '✅ Added: $title${withCover ? ' (with cover)' : ''}',
      '✅ Hinzugefügt: $title${withCover ? ' (mit Cover)' : ''}');

  // ===================== Statystyki =====================
  /// Nazwa gatunku w aktualnym jezyku (zastepuje globalne genreName()).
  String genreName(String genre) {
    switch (genre) {
      case 'rock': return 'Rock';
      case 'pop': return 'Pop';
      case 'metal': return 'Metal';
      case 'jazz': return 'Jazz';
      case 'classical': return _t('Klasyczna', 'Classical', 'Klassik');
      case 'electronic': return _t('Elektroniczna', 'Electronic', 'Elektronisch');
      case 'hip-hop': return 'Hip-Hop';
      case 'blues': return 'Blues';
      case 'country': return 'Country';
      case 'reggae': return 'Reggae';
      case 'soul': return 'Soul/R&B';
      case 'punk': return 'Punk';
      case 'folk': return 'Folk';
      case 'disco': return 'Disco';
      default: return _t('Inne', 'Other', 'Sonstige');
    }
  }

  String get genresSection => _t('Gatunki', 'Genres', 'Genres');
  String get formatsSection => _t('Formaty', 'Formats', 'Formate');
  String get topArtists => _t('Top artyści', 'Top artists', 'Top-Künstler');
  String get albumsByYear => _t('Albumy według lat', 'Albums by year', 'Alben nach Jahr');
  String get noData => _t('Brak danych', 'No data', 'Keine Daten');
  String get noYearData =>
      _t('Brak danych o latach', 'No year data', 'Keine Jahresdaten');
  String albumsAbbrev(int n) => _t('$n alb.', '$n alb.', '$n Alb.');

  // ===================== Historia =====================
  String get topAlbums => _t('Top Albumy', 'Top Albums', 'Top-Alben');
  String get topTracks => _t('Top Utwory', 'Top Tracks', 'Top-Titel');
  String get clearHistory => _t('Wyczyść historię', 'Clear history', 'Verlauf löschen');
  String get noHistory =>
      _t('Brak historii słuchania', 'No listening history', 'Kein Wiedergabeverlauf');
  String get noHistoryDesc => _t('Odtwórz muzykę, a pojawi się tutaj!',
      'Play some music and it will appear here!', 'Spiele Musik ab, dann erscheint sie hier!');
  String get clearHistoryConfirmTitle =>
      _t('Wyczyścić historię?', 'Clear history?', 'Verlauf löschen?');
  String get clearHistoryConfirm => _t('Ta operacja usunie całą historię słuchania.',
      'This will delete all listening history.', 'Dies löscht den gesamten Wiedergabeverlauf.');
  String get historyCleared =>
      _t('Historia wyczyszczona', 'History cleared', 'Verlauf gelöscht');

  // ===================== Ustawienia dzwieku =====================
  String get crossfadeSection =>
      _t('Płynne przejścia (Crossfade)', 'Crossfade', 'Überblendung (Crossfade)');
  String get enableCrossfade => _t('Włącz crossfade', 'Enable crossfade', 'Crossfade aktivieren');
  String get crossfadeDesc => _t('Płynne przejście między utworami',
      'Smooth transition between tracks', 'Sanfter Übergang zwischen Titeln');
  String get crossfadeDuration =>
      _t('Czas przejścia', 'Transition time', 'Übergangszeit');
  String secondsCount(int n) => _t('$n sekund', '$n seconds', '$n Sekunden');
  String get openSystemEq =>
      _t('Otwórz systemowy equalizer', 'Open system equalizer', 'System-Equalizer öffnen');
  String get eqDesc => _t('Dostosuj tony niskie i wysokie',
      'Adjust bass and treble', 'Bässe und Höhen anpassen');
  String get crossfadeInfo => _t(
      '• Crossfade tworzy płynne przejście między utworami\n\n',
      '• Crossfade creates a smooth transition between tracks\n\n',
      '• Crossfade sorgt für sanfte Übergänge zwischen Titeln\n\n');
  String get eqInfo => _t(
      '• Equalizer systemowy pozwala dostosować częstotliwości dla wszystkich aplikacji',
      '• The system equalizer lets you adjust frequencies for all apps',
      '• Der System-Equalizer passt die Frequenzen für alle Apps an');
  String get eqInstructions => _t(
      'Aby otworzyć equalizer:\n\n1. Otwórz Ustawienia telefonu\n2. Przejdź do: Dźwięk i wibracje\n3. Znajdź: Jakość dźwięku / Equalizer\n\nLub pobierz aplikację Equalizer ze Sklepu Play.',
      'To open the equalizer:\n\n1. Open phone Settings\n2. Go to: Sound & vibration\n3. Find: Sound quality / Equalizer\n\nOr download an Equalizer app from the Play Store.',
      'So öffnest du den Equalizer:\n\n1. Telefon-Einstellungen öffnen\n2. Zu: Ton & Vibration\n3. Finde: Klangqualität / Equalizer\n\nOder lade eine Equalizer-App aus dem Play Store.');
  String get playStore => _t('Sklep Play', 'Play Store', 'Play Store');

  // ===================== Rozpoznawanie utworu =====================
  // ===================== Import z dysku (web) =====================
  String get pickFromDisk =>
      _t('Wybierz pliki z dysku', 'Pick files from disk', 'Dateien von der Festplatte wählen');
  String get pickFromDiskSub =>
      _t('Dodaj utwory z komputera', 'Add tracks from your computer', 'Titel vom Computer hinzufügen');
  String get importFromDisk => _t('Import z dysku', 'Disk import', 'Import von Festplatte');
  String get variousArtists =>
      _t('Różni artyści', 'Various artists', 'Verschiedene Künstler');
  String get webSessionNote => _t(
      'Pliki będzie można odtwarzać do zamknięcia karty przeglądarki',
      'Files remain playable until you close the browser tab',
      'Dateien bleiben bis zum Schließen des Browser-Tabs abspielbar');

  String get recognizeWith =>
      _t('Rozpoznaj utwór za pomocą:', 'Recognize a song with:', 'Song erkennen mit:');
  String get getFromPlayStore =>
      _t('Pobierz ze Sklepu Play', 'Get from Play Store', 'Aus dem Play Store laden');
  String getApp(String name) => _t('Pobierz $name', 'Get $name', '$name laden');
  String openApp(String name) => _t('Otwórz $name', 'Open $name', '$name öffnen');
  String get appInstalled =>
      _t('Aplikacja zainstalowana', 'App installed', 'App installiert');
  String get searchLyricsGoogle =>
      _t('Szukaj tekstu w Google', 'Search lyrics on Google', 'Songtext bei Google suchen');
  String get recognizeHint => _t(
      'Po zainstalowaniu Shazam lub SoundHound,\nuruchom je ręcznie z ekranu głównego.',
      'After installing Shazam or SoundHound,\nlaunch them manually from the home screen.',
      'Nach der Installation von Shazam oder SoundHound\nstarte sie manuell vom Startbildschirm.');

  // ===================== Karaoke =====================
  String noLyricsFor(String title) => _t('Nie znaleziono tekstu dla „$title"',
      'No lyrics found for "$title"', 'Kein Songtext für „$title" gefunden');
  String get lyricsError =>
      _t('Błąd pobierania tekstu', 'Error fetching lyrics', 'Fehler beim Laden des Songtexts');
  String get searchingLyrics => _t('Szukam tekstu...', 'Searching lyrics...', 'Suche Songtext...');
  String get tryAgain => _t('Spróbuj ponownie', 'Try again', 'Erneut versuchen');
  String get noLyrics => _t('Brak tekstu', 'No lyrics', 'Kein Songtext');

  String get about => _t('O aplikacji', 'About', 'Über die App');
  String get aboutDescription => _t('Aplikacja do zarządzania kolekcją muzyczną.',
      'App for managing your music collection.', 'App zur Verwaltung deiner Musiksammlung.');
  String version(String v) => _t('Wersja $v', 'Version $v', 'Version $v');
}
