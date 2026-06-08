import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../models/album.dart';
import 'database_service.dart';

class BackupService extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );
  
  GoogleSignInAccount? _currentUser;
  bool _isLoading = false;
  String? _lastBackupDate;
  
  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get lastBackupDate => _lastBackupDate;

  BackupService() {
    _init();
  }

  Future<void> _init() async {
    _googleSignIn.onCurrentUserChanged.listen((account) {
      _currentUser = account;
      notifyListeners();
    });
    
    // Sprawdz czy juz zalogowany
    _currentUser = await _googleSignIn.signInSilently();
    notifyListeners();
  }

  // Logowanie do Google
  Future<bool> signIn() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      _currentUser = await _googleSignIn.signIn();
      
      _isLoading = false;
      notifyListeners();
      
      return _currentUser != null;
    } catch (e) {
      debugPrint('Google Sign In error: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Wylogowanie
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    notifyListeners();
  }

  // Tworzenie backupu
  Future<bool> createBackup(DatabaseService db) async {
    if (_currentUser == null) return false;
    
    try {
      _isLoading = true;
      notifyListeners();
      
      // Pobierz klienta HTTP
      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      final driveApi = drive.DriveApi(httpClient);
      
      // Przygotuj dane do backupu
      final backupData = {
        'version': 1,
        'date': DateTime.now().toIso8601String(),
        'albums': db.allAlbums.map((a) => {
          'id': a.id,
          'artist': a.artist,
          'title': a.title,
          'year': a.year,
          'genre': a.genre,
          'format': a.format,
          'rating': a.rating,
          'isFavorite': a.isFavorite,
          'isWishlist': a.isWishlist,
          'notes': a.notes,
          'coverUrl': a.coverUrl,
          'tracks': a.tracks.map((t) => {
            'title': t.title,
            'filePath': t.filePath,
            'durationSeconds': t.durationSeconds,
            'trackNumber': t.trackNumber,
          }).toList(),
        }).toList(),
      };
      
      final jsonString = jsonEncode(backupData);
      final bytes = utf8.encode(jsonString);
      
      // Sprawdz czy istnieje juz plik backupu
      final existingFiles = await driveApi.files.list(
        q: "name = 'kolekcja_muzyki_backup.json' and trashed = false",
        spaces: 'drive',
      );
      
      // Usun stary backup
      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        for (var file in existingFiles.files!) {
          await driveApi.files.delete(file.id!);
        }
      }
      
      // Utworz nowy plik
      final driveFile = drive.File()
        ..name = 'kolekcja_muzyki_backup.json'
        ..mimeType = 'application/json';
      
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
      );
      
      await driveApi.files.create(
        driveFile,
        uploadMedia: media,
      );
      
      _lastBackupDate = DateTime.now().toString().substring(0, 16);
      _isLoading = false;
      notifyListeners();
      
      return true;
    } catch (e) {
      debugPrint('Backup error: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Przywracanie backupu
  Future<int> restoreBackup(DatabaseService db) async {
    if (_currentUser == null) return -1;
    
    try {
      _isLoading = true;
      notifyListeners();
      
      // Pobierz klienta HTTP
      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) {
        _isLoading = false;
        notifyListeners();
        return -1;
      }
      
      final driveApi = drive.DriveApi(httpClient);
      
      // Znajdz plik backupu
      final files = await driveApi.files.list(
        q: "name = 'kolekcja_muzyki_backup.json' and trashed = false",
        spaces: 'drive',
      );
      
      if (files.files == null || files.files!.isEmpty) {
        _isLoading = false;
        notifyListeners();
        return 0; // Brak backupu
      }
      
      final fileId = files.files!.first.id!;
      
      // Pobierz zawartosc pliku
      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final bytes = <int>[];
      await for (var chunk in response.stream) {
        bytes.addAll(chunk);
      }
      
      final jsonString = utf8.decode(bytes);
      final backupData = jsonDecode(jsonString);
      
      // Przywroc albumy
      int restoredCount = 0;
      final albumsData = backupData['albums'] as List;
      
      for (var albumData in albumsData) {
        // Sprawdz czy album juz istnieje
        if (!db.isDuplicate(albumData['artist'], albumData['title'])) {
          final tracks = (albumData['tracks'] as List).map((t) => Track(
            title: t['title'],
            filePath: t['filePath'],
            durationSeconds: t['durationSeconds'],
            trackNumber: t['trackNumber'] ?? 0,
          )).toList();
          
          final album = Album(
            id: albumData['id'],
            artist: albumData['artist'],
            title: albumData['title'],
            year: albumData['year'],
            genre: albumData['genre'],
            format: albumData['format'],
            rating: albumData['rating'],
            isFavorite: albumData['isFavorite'] ?? false,
            isWishlist: albumData['isWishlist'] ?? false,
            notes: albumData['notes'],
            coverUrl: albumData['coverUrl'],
            tracks: tracks,
          );
          
          await db.addAlbum(album);
          restoredCount++;
        }
      }
      
      _isLoading = false;
      notifyListeners();
      
      return restoredCount;
    } catch (e) {
      debugPrint('Restore error: $e');
      _isLoading = false;
      notifyListeners();
      return -1;
    }
  }
}
