import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/album.dart';

class AudioService extends ChangeNotifier {
  Function(String albumId, String trackTitle, int durationSeconds)? onTrackPlayed;
  AudioService() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [_equalizer],
      ),
    );
    _init();
  }
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  late final AudioPlayer _player;
  final OnAudioQuery _audioQuery = OnAudioQuery();
  
  // Stan odtwarzacza
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // Aktualnie odtwarzane
  Album? _currentAlbum;
  int _currentTrackIndex = 0;
  Track? _currentTrack;
  
  // Tryby
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  
  // Crossfade
  bool _crossfadeEnabled = false;
  int _crossfadeDuration = 3; // sekundy
  
  // Gettery
  AudioPlayer get player => _player;
  AndroidEqualizer get equalizer => _equalizer;
  int? get audioSessionId => _player.androidAudioSessionId;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  Album? get currentAlbum => _currentAlbum;
  int get currentTrackIndex => _currentTrackIndex;
  Track? get currentTrack => _currentTrack;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  bool get crossfadeEnabled => _crossfadeEnabled;
  int get crossfadeDuration => _crossfadeDuration;
  
  double get progress {
    if (_duration.inMilliseconds == 0) return 0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }

  

  void _init() {
    // Nasluchuj zmian stanu
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isLoading = state.processingState == ProcessingState.loading ||
                   state.processingState == ProcessingState.buffering;
      notifyListeners();
    });

    // Nasluchuj pozycji
    _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    // Nasluchuj czasu trwania
    _player.durationStream.listen((dur) {
      _duration = dur ?? Duration.zero;
      notifyListeners();
    });

    // Automatyczne przejscie do nastepnego utworu
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onTrackComplete();
      }
    });
  }

  // Sprawdz i popros o uprawnienia
  Future<bool> checkPermissions() async {
    // Android 13+ wymaga READ_MEDIA_AUDIO
    if (Platform.isAndroid) {
      final status = await Permission.audio.request();
      if (status.isGranted) return true;
      
      // Fallback dla starszych wersji
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return true;
  }

  // Skanuj pliki muzyczne na telefonie
  Future<List<SongModel>> scanMusicFiles() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Brak uprawnien do odczytu plikow');
    }

    return await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
  }

  // Skanuj albumy na telefonie
  Future<List<AlbumModel>> scanAlbums() async {
    final hasPermission = await checkPermissions();
    if (!hasPermission) {
      throw Exception('Brak uprawnien do odczytu plikow');
    }

    return await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
  }

  // Pobierz utwory z albumu (po ID albumu z systemu)
  Future<List<SongModel>> getSongsFromAlbum(int albumId) async {
    return await _audioQuery.queryAudiosFrom(
      AudiosFromType.ALBUM_ID,
      albumId,
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
    );
  }

  // Konwertuj SongModel do Track
  Track songToTrack(SongModel song) {
    return Track(
      title: song.title,
      filePath: song.data, // PELNA SCIEZKA DO PLIKU!
      durationSeconds: (song.duration ?? 0) ~/ 1000,
      trackNumber: song.track ?? 0,
    );
  }

  // Konwertuj AlbumModel do Album
  Future<Album> albumModelToAlbum(AlbumModel albumModel) async {
    final songs = await getSongsFromAlbum(albumModel.id);
    final tracks = songs.map((s) => songToTrack(s)).toList();
    
    // Sortuj po numerze sciezki
    tracks.sort((a, b) => a.trackNumber.compareTo(b.trackNumber));

    return Album(
      id: 'device_${albumModel.id}',
      artist: albumModel.artist ?? 'Nieznany artysta',
      title: albumModel.album,
      year: null, // AlbumModel nie ma roku
      genre: 'other',
      format: 'digital',
      rating: 3,
      tracks: tracks,
    );
  }

  // Odtworz utwor
  Future<void> playTrack(Album album, int trackIndex) async {
    if (trackIndex < 0 || trackIndex >= album.tracks.length) return;
    
    final track = album.tracks[trackIndex];
    if (!track.hasFile) {
      throw Exception('Brak pliku dla tego utworu');
    }

    _currentAlbum = album;
    _currentTrackIndex = trackIndex;
    _currentTrack = track;
    _isLoading = true;
    notifyListeners();

    try {
      await _player.setFilePath(track.filePath!);
      await _player.play();
        onTrackPlayed?.call(_currentAlbum!.id, _currentTrack!.title, _currentTrack!.durationSeconds ?? 0);
    } catch (e) {
      debugPrint('Blad odtwarzania: $e');
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Odtworz album od poczatku
  Future<void> playAlbum(Album album) async {
    if (album.tracks.isEmpty) return;
    
    // Znajdz pierwszy utwor z plikiem
    int firstPlayable = 0;
    for (int i = 0; i < album.tracks.length; i++) {
      if (album.tracks[i].hasFile) {
        firstPlayable = i;
        break;
      }
    }
    
    await playTrack(album, firstPlayable);
  }

  // Play/Pause
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
        onTrackPlayed?.call(_currentAlbum!.id, _currentTrack!.title, _currentTrack!.durationSeconds ?? 0);
    }
  }

  // Nastepny utwor
  Future<void> nextTrack() async {
    if (_currentAlbum == null) return;
    
    int nextIndex = _currentTrackIndex + 1;
    
    // Znajdz nastepny utwor z plikiem
    while (nextIndex < _currentAlbum!.tracks.length) {
      if (_currentAlbum!.tracks[nextIndex].hasFile) {
        await playTrack(_currentAlbum!, nextIndex);
        return;
      }
      nextIndex++;
    }
    
    // Koniec albumu - sprawdz loop mode
    if (_loopMode == LoopMode.all) {
      // Wroc do poczatku
      for (int i = 0; i < _currentAlbum!.tracks.length; i++) {
        if (_currentAlbum!.tracks[i].hasFile) {
          await playTrack(_currentAlbum!, i);
          return;
        }
      }
    } else {
      // Zatrzymaj
      await stop();
    }
  }

  // Poprzedni utwor
  Future<void> previousTrack() async {
    if (_currentAlbum == null) return;
    
    // Jesli pozycja > 3s, wroc na poczatek utworu
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    
    int prevIndex = _currentTrackIndex - 1;
    
    // Znajdz poprzedni utwor z plikiem
    while (prevIndex >= 0) {
      if (_currentAlbum!.tracks[prevIndex].hasFile) {
        await playTrack(_currentAlbum!, prevIndex);
        return;
      }
      prevIndex--;
    }
    
    // Poczatek albumu - wroc na poczatek pierwszego utworu
    await _player.seek(Duration.zero);
  }

  // Przewin do pozycji
  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  // Przewin procentowo
  Future<void> seekToPercent(double percent) async {
    final newPosition = Duration(
      milliseconds: (_duration.inMilliseconds * percent).toInt(),
    );
    await seekTo(newPosition);
  }

  // Stop
  Future<void> stop() async {
    await _player.stop();
    _currentAlbum = null;
    _currentTrack = null;
    _currentTrackIndex = 0;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }

  // Toggle shuffle
  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  // Przelacz loop mode
  void toggleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        _player.setLoopMode(LoopMode.one);
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        _player.setLoopMode(LoopMode.off);
        break;
    }
    notifyListeners();
  }

  // Callback po zakonczeniu utworu
  void _onTrackComplete() {
    if (_loopMode == LoopMode.one) {
      // Powtorz ten sam utwor (obslugiwane przez AudioPlayer)
      return;
    }
    nextTrack();
  }

  // Formatuj czas
  static String formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // Crossfade - wlacz/wylacz
  void setCrossfade(bool enabled) {
    _crossfadeEnabled = enabled;
    notifyListeners();
  }

  // Crossfade - ustaw czas trwania (1-10 sekund)
  void setCrossfadeDuration(int seconds) {
    _crossfadeDuration = seconds.clamp(1, 10);
    notifyListeners();
  }

  // Crossfade effect - fade out current, fade in next
  Future<void> _fadeToNext(Future<void> Function() loadNext) async {
    if (!_crossfadeEnabled || _crossfadeDuration <= 0) {
      await loadNext();
      return;
    }

    final steps = 20;
    final stepDuration = (_crossfadeDuration * 1000 / steps).round();
    final volumeStep = 1.0 / steps;

    // Fade out
    for (int i = 0; i < steps; i++) {
      await _player.setVolume(1.0 - (volumeStep * i));
      await Future.delayed(Duration(milliseconds: stepDuration ~/ 2));
    }

    // Load next track
    await loadNext();

    // Fade in
    for (int i = 0; i < steps; i++) {
      await _player.setVolume(volumeStep * i);
      await Future.delayed(Duration(milliseconds: stepDuration ~/ 2));
    }
    
    await _player.setVolume(1.0);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}










