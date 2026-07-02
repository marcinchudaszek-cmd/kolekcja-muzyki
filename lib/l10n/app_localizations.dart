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
  String get about => _t('O aplikacji', 'About', 'Über die App');
  String get aboutDescription => _t('Aplikacja do zarządzania kolekcją muzyczną.',
      'App for managing your music collection.', 'App zur Verwaltung deiner Musiksammlung.');
  String version(String v) => _t('Wersja $v', 'Version $v', 'Version $v');
}
