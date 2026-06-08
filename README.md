# Kolekcja Muzyki

Aplikacja mobilna (Flutter) do zarządzania własną kolekcją muzyki — pełnoprawny
odtwarzacz z dostępem do plików, katalogiem albumów i backupem w chmurze.

- **Nazwa w sklepie:** Kolekcja Muzyki
- **Pakiet:** `com.beagleappsstudio.kolekcjamuzyki`
- **Wydawca:** Beagle Apps Studio
- **Wersja:** 1.3.3 (build 19)

## Funkcje

- 🎵 Odtwarzacz audio z odtwarzaniem w tle i equalizerem
- 💿 Katalog kolekcji — albumy, płyty CD, winyle
- 📷 Skaner kodów kreskowych do dodawania płyt
- 🖼️ Automatyczne pobieranie okładek (MusicBrainz)
- 📂 Skanowanie plików muzycznych z urządzenia
- ☁️ Backup i przywracanie z Google Drive
- 📊 Statystyki i historia odsłuchań

## Stack

- Flutter / Dart (SDK `>=3.0.0 <4.0.0`)
- `just_audio` + `just_audio_background` — odtwarzanie
- `hive` — lokalna baza danych
- `google_sign_in` + `googleapis` — backup na Google Drive
- `mobile_scanner` — skaner kodów
- `provider` — zarządzanie stanem

## Uruchomienie

```bash
flutter pub get
flutter run
```

Build produkcyjny (Android):

```bash
flutter build appbundle --release
```
