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

  String get about => _t('O aplikacji', 'About', 'Über die App');
  String get aboutDescription => _t('Aplikacja do zarządzania kolekcją muzyczną.',
      'App for managing your music collection.', 'App zur Verwaltung deiner Musiksammlung.');
  String version(String v) => _t('Wersja $v', 'Version $v', 'Version $v');
}
