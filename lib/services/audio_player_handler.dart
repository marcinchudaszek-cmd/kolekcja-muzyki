import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/album.dart';

/// Rdzen odtwarzania oparty o [audio_service].
///
/// Laczy odtwarzanie [just_audio] z sesja medialna systemu Android, dzieki
/// czemu dziala sterowanie z ekranu blokady, powiadomienie odtwarzacza ORAZ
/// Android Auto (przegladanie kolekcji przez [getChildren]).
///
/// Cala logika odtwarzania zyje tutaj. Klasa [AudioService] (ChangeNotifier)
/// jest tylko cienka fasada delegujaca do tego handlera i powiadamiajaca UI.
class AudioPlayerHandler extends BaseAudioHandler {
  AudioPlayerHandler() {
    _playerA = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [_equalizer]),
    );
    _playerB = AudioPlayer(
      audioPipeline: AudioPipeline(androidAudioEffects: [_equalizerB]),
    );
    _init();
    unawaited(_loadSettings());
  }

  /// Equalizer sterowany z UI (nalezy do gracza A) oraz jego kopia dla gracza B.
  /// Ustawienia sa lustrzane — patrz [setEqualizerBandGain] / [_syncEqualizerTo].
  final AndroidEqualizer _equalizer = AndroidEqualizer();
  final AndroidEqualizer _equalizerB = AndroidEqualizer();
  final Random _random = Random();

  /// Crossfade wymaga nakladania sie dwoch utworow, wiec dwoch odtwarzaczy.
  /// [_player] to ten, ktory aktualnie "jest" biezacym utworem;
  /// [_standby] to drugi — uzywany do przygotowania nastepnego utworu.
  late final AudioPlayer _playerA;
  late final AudioPlayer _playerB;
  bool _useA = true;
  AudioPlayer get _player => _useA ? _playerA : _playerB;
  AudioPlayer get _standby => _useA ? _playerB : _playerA;
  AndroidEqualizer get _standbyEqualizer => _useA ? _equalizerB : _equalizer;

  /// Wywolywane przy kazdej zmianie stanu — fasada podpina tu notifyListeners.
  VoidCallback? onChanged;

  /// Callback do zapisu historii odtwarzania (uzywany przez HomeScreen).
  void Function(String albumId, String trackTitle, int durationSeconds)?
      onTrackPlayed;

  /// Zamienia surowa sciezke pliku na content:// URI z MediaStore.
  /// Ustawiany przez fasade (uzywa on_audio_query). Konieczny, bo na
  /// Androidzie 13+ ExoPlayer nie moze otworzyc plikow w pamieci
  /// wspoldzielonej po surowej sciezce (EACCES) — tylko po content URI.
  Future<String?> Function(String path)? resolveUri;

  // Stan odtwarzania
  Album? _currentAlbum;
  int _currentTrackIndex = 0;
  Track? _currentTrack;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  bool _crossfadeEnabled = false;
  int _crossfadeDuration = 3; // sekundy
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Android Auto: w trakcie zmiany utworu odtwarzacz przechodzi przez stan
  // idle, ktory AA interpretuje jako "koniec odtwarzania" i zamyka ekran
  // now-playing. Ten flag pozwala zamiast idle raportowac loading.
  bool _switchingTrack = false;
  // Id albumu, dla ktorego opublikowano kolejke - unikamy ponownej publikacji
  // przy zmianie utworu w tym samym albumie (AA rebuildowaloby widok).
  String? _queueAlbumId;

  // Gettery
  AudioPlayer get player => _player;
  AndroidEqualizer get equalizer => _equalizer;
  int? get audioSessionId => _player.androidAudioSessionId;
  bool get isPlaying => _player.playing;
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
    // Subskrybujemy OBA odtwarzacze, ale reagujemy tylko na ten aktywny —
    // drugi w tle przygotowuje/dogrywa utwor podczas crossfade.
    for (final p in [_playerA, _playerB]) {
      p.playbackEventStream.listen((event) {
        if (!identical(p, _player)) return;
        _broadcastState(event);
      });

      p.playerStateStream.listen((state) {
        if (!identical(p, _player)) return;
        _isLoading = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        onChanged?.call();
      });

      p.positionStream.listen((pos) {
        if (!identical(p, _player)) return;
        _position = pos;
        onChanged?.call();
        _maybeStartCrossfade();
      });

      p.durationStream.listen((dur) {
        if (!identical(p, _player)) return;
        _duration = dur ?? Duration.zero;
        onChanged?.call();
      });

      // Automatyczne przejscie do nastepnego utworu.
      p.processingStateStream.listen((state) {
        if (!identical(p, _player)) return;
        if (state == ProcessingState.completed) {
          // Przy crossfade nastepny utwor juz gra — nie przeskakuj drugi raz.
          if (_crossfading) return;
          _onTrackComplete();
        }
      });
    }
  }

  // ----- Ustawienia trwale -----

  static const _prefsCrossfadeEnabled = 'crossfade_enabled';
  static const _prefsCrossfadeDuration = 'crossfade_duration';

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _crossfadeEnabled = prefs.getBool(_prefsCrossfadeEnabled) ?? false;
      _crossfadeDuration = prefs.getInt(_prefsCrossfadeDuration) ?? 3;
      onChanged?.call();
    } catch (e) {
      debugPrint('Nie udalo sie wczytac ustawien odtwarzania: $e');
    }
  }

  // ----- Equalizer (lustrzany na obu odtwarzaczach) -----

  /// Kopiuje ustawienia equalizera z gracza A na wskazany equalizer, zeby
  /// po crossfade brzmienie sie nie zmienilo.
  Future<void> _syncEqualizerTo(AndroidEqualizer target) async {
    try {
      await target.setEnabled(_equalizer.enabled);
      final src = await _equalizer.parameters;
      final dst = await target.parameters;
      for (int i = 0; i < src.bands.length && i < dst.bands.length; i++) {
        await dst.bands[i].setGain(src.bands[i].gain);
      }
    } catch (e) {
      debugPrint('Sync equalizera nieudany: $e');
    }
  }

  /// Wlacza/wylacza equalizer na obu odtwarzaczach.
  Future<void> setEqualizerEnabled(bool enabled) async {
    await _equalizer.setEnabled(enabled);
    await _equalizerB.setEnabled(enabled);
  }

  /// Ustawia wzmocnienie pasma na obu odtwarzaczach (UI podaje indeks pasma).
  Future<void> setEqualizerBandGain(int index, double gain) async {
    for (final eq in [_equalizer, _equalizerB]) {
      try {
        final params = await eq.parameters;
        if (index < params.bands.length) {
          await params.bands[index].setGain(gain);
        }
      } catch (e) {
        debugPrint('Ustawienie pasma equalizera nieudane: $e');
      }
    }
  }

  // ----- Crossfade -----

  Timer? _fadeTimer;
  bool _crossfading = false;

  /// Ktory utwor pojdzie jako nastepny (respektuje shuffle i tryb powtarzania).
  /// Wspoldzielone przez [nextTrack] i crossfade, zeby oba szly tak samo.
  int? _nextIndex() {
    final album = _currentAlbum;
    if (album == null) return null;
    final playable = _playableIndexes;
    if (playable.isEmpty) return null;

    if (_shuffle) {
      if (playable.length == 1) return playable.first;
      final candidates =
          playable.where((i) => i != _currentTrackIndex).toList();
      return candidates[_random.nextInt(candidates.length)];
    }

    for (int i = _currentTrackIndex + 1; i < album.tracks.length; i++) {
      if (album.tracks[i].hasFile) return i;
    }
    if (_loopMode == LoopMode.all) return playable.first;
    return null;
  }

  /// Odpala crossfade gdy do konca utworu zostalo tyle, ile trwa przejscie.
  void _maybeStartCrossfade() {
    if (!_crossfadeEnabled || _crossfading) return;
    if (_loopMode == LoopMode.one) return;
    if (!_player.playing) return;

    final total = _player.duration;
    if (total == null) return;
    // Utwor krotszy niz samo przejscie — crossfade nie ma sensu.
    if (total.inMilliseconds <= (_crossfadeDuration + 1) * 1000) return;

    final remaining = total - _position;
    if (remaining.inMilliseconds <= 0) return;
    if (remaining.inMilliseconds > _crossfadeDuration * 1000) return;

    final next = _nextIndex();
    if (next == null) return;
    unawaited(_startCrossfade(next));
  }

  Future<void> _startCrossfade(int nextIndex) async {
    final album = _currentAlbum;
    if (album == null || _crossfading) return;
    _crossfading = true;

    final from = _player;
    final to = _standby;

    try {
      await _syncEqualizerTo(_standbyEqualizer);
      await to.setVolume(0);
      await to.setAudioSource(await _audioSourceFor(album.tracks[nextIndex]));
      unawaited(to.play());
    } catch (e) {
      debugPrint('Crossfade — nie udalo sie przygotowac nastepnego utworu: $e');
      _crossfading = false;
      try {
        await to.stop();
      } catch (_) {}
      await to.setVolume(1.0);
      return;
    }

    const stepMs = 60;
    final steps = ((_crossfadeDuration * 1000) / stepMs).round().clamp(1, 2000);
    int step = 0;
    bool busy = false;

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) async {
      if (busy) return; // nie nakladaj wywolan setVolume
      busy = true;
      try {
        step++;
        final p = (step / steps).clamp(0.0, 1.0);
        await from.setVolume(1.0 - p);
        await to.setVolume(p);
        if (p >= 1.0) {
          t.cancel();
          await _finishCrossfade(from, to, nextIndex);
        }
      } catch (e) {
        debugPrint('Crossfade — blad przejscia: $e');
        t.cancel();
        await _finishCrossfade(from, to, nextIndex);
      } finally {
        busy = false;
      }
    });
  }

  Future<void> _finishCrossfade(
      AudioPlayer from, AudioPlayer to, int index) async {
    _fadeTimer?.cancel();
    _fadeTimer = null;

    final album = _currentAlbum;
    // Przelacz aktywny odtwarzacz na ten, ktory teraz gra.
    _useA = identical(to, _playerA);
    _currentTrackIndex = index;
    _currentTrack = (album != null && index < album.tracks.length)
        ? album.tracks[index]
        : null;

    await to.setVolume(1.0);
    try {
      await from.stop();
    } catch (_) {}
    await from.setVolume(1.0);

    // Odswiez stan z nowego aktywnego gracza — jego zdarzenia duration/position
    // byly odfiltrowane, dopoki gral w tle.
    _duration = to.duration ?? Duration.zero;
    _position = to.position;
    _isLoading = false;

    _crossfading = false;

    if (album != null && _currentTrack != null) {
      mediaItem.add(_trackToMediaItem(album, index, duration: to.duration));
      onTrackPlayed?.call(
        album.id,
        _currentTrack!.title,
        _currentTrack!.durationSeconds ?? 0,
      );
    }
    _broadcastState();
    onChanged?.call();
  }

  /// Przerywa trwajace przejscie (np. gdy user sam zmieni utwor).
  Future<void> _cancelCrossfade() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (!_crossfading) {
      await _player.setVolume(1.0);
      return;
    }
    _crossfading = false;
    final standby = _standby;
    try {
      await standby.stop();
    } catch (_) {}
    await standby.setVolume(1.0);
    await _player.setVolume(1.0);
  }

  void _broadcastState([PlaybackEvent? event]) {
    final playing = _player.playing;
    final raw = _player.processingState;
    // W trakcie przelaczania utworu nie raportuj idle (AA zamkneloby ekran).
    final processingState = (_switchingTrack && raw == ProcessingState.idle)
        ? AudioProcessingState.loading
        : const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[raw]!;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentTrackIndex,
    ));
  }

  // ----- Metadane / okladki -----

  Uri? _albumArtUri(Album album) {
    // Preferuj URL sieciowy — Android Auto dziala w osobnym procesie i nie
    // odczyta lokalnego file://. Sciezka lokalna zostaje jako fallback (dziala
    // w powiadomieniu / na ekranie blokady tego samego procesu).
    final url = album.coverUrl;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) return uri;
    }
    final path = album.coverPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Uri.file(path);
    }
    return null;
  }

  MediaItem _trackToMediaItem(Album album, int index, {Duration? duration}) {
    final t = album.tracks[index];
    return MediaItem(
      id: 'track/${album.id}/$index',
      title: t.title,
      album: album.title,
      artist: album.artist,
      duration: duration ??
          (t.durationSeconds != null && t.durationSeconds! > 0
              ? Duration(seconds: t.durationSeconds!)
              : null),
      artUri: _albumArtUri(album),
      playable: true,
    );
  }

  /// Buduje zrodlo audio dla utworu. Preferuje content:// URI (dziala z
  /// uprawnieniem READ_MEDIA_AUDIO na Androidzie 13+); surowa sciezka pliku
  /// jest tylko fallbackiem dla plikow w prywatnej pamieci aplikacji.
  Future<AudioSource> _audioSourceFor(Track track) async {
    final path = track.filePath!;
    // content:// (Android MediaStore), blob: (import z dysku na web) i http(s)
    // sa juz gotowymi URI - nie mapuj ich.
    if (path.startsWith('content://') ||
        path.startsWith('blob:') ||
        path.startsWith('http')) {
      return AudioSource.uri(Uri.parse(path));
    }
    // Mapuj surowa sciezke na content:// URI (wymagane na Androidzie 10+).
    final resolved = await resolveUri?.call(path);
    if (resolved != null && resolved.isNotEmpty) {
      return AudioSource.uri(Uri.parse(resolved));
    }
    // Fallback dla plikow w prywatnej pamieci aplikacji.
    return AudioSource.uri(Uri.file(path));
  }

  // ----- Sterowanie odtwarzaniem (uzywane przez fasade i UI) -----

  Future<void> playTrack(Album album, int trackIndex) async {
    if (trackIndex < 0 || trackIndex >= album.tracks.length) return;

    final track = album.tracks[trackIndex];
    if (!track.hasFile) {
      throw Exception('Brak pliku dla tego utworu');
    }

    // Reczne uruchomienie utworu przerywa trwajace przejscie i przywraca
    // pelna glosnosc (crossfade mogl zostawic gracza wyciszonego).
    await _cancelCrossfade();

    _currentAlbum = album;
    _currentTrackIndex = trackIndex;
    _currentTrack = track;
    _isLoading = true;
    _switchingTrack = true;
    onChanged?.call();

    // Kolejke publikuj tylko przy zmianie albumu (nie przy kazdym utworze —
    // AA rebuildowaloby wtedy caly widok now-playing).
    if (_queueAlbumId != album.id) {
      queue.add([
        for (int i = 0; i < album.tracks.length; i++)
          _trackToMediaItem(album, i),
      ]);
      _queueAlbumId = album.id;
    }
    mediaItem.add(_trackToMediaItem(album, trackIndex));

    try {
      final loaded = await _player.setAudioSource(await _audioSourceFor(track));
      _switchingTrack = false;
      // Ustaw realny czas trwania (skan folderu daje 0s) — dzieki temu
      // Android Auto pokazuje poprawny pasek postepu.
      if (loaded != null) {
        mediaItem.add(_trackToMediaItem(album, trackIndex, duration: loaded));
      }
      _broadcastState();
      // UWAGA: na Androidzie Future z play() konczy sie dopiero przy koncu
      // utworu (STATE_ENDED), nie przy starcie odtwarzania. Awaitowanie go
      // wstrzymywalo kod wywolujacy (nawigacje, historie) do konca utworu,
      // a przerwanie przez "nastepny" odpalalo te zalegle kontynuacje
      // w losowych momentach (np. zdejmowalo ekran odtwarzacza).
      unawaited(_player.play());
      onTrackPlayed?.call(album.id, track.title, track.durationSeconds ?? 0);
    } catch (e) {
      debugPrint('Blad odtwarzania: $e');
      _isLoading = false;
      _switchingTrack = false;
      onChanged?.call();
      rethrow;
    }
  }

  Future<void> playAlbum(Album album) async {
    if (album.tracks.isEmpty) return;

    int firstPlayable = 0;
    for (int i = 0; i < album.tracks.length; i++) {
      if (album.tracks[i].hasFile) {
        firstPlayable = i;
        break;
      }
    }

    await playTrack(album, firstPlayable);
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      // play() konczy sie dopiero na koncu utworu - nie czekaj (patrz playTrack).
      unawaited(_player.play());
      if (_currentAlbum != null && _currentTrack != null) {
        onTrackPlayed?.call(
          _currentAlbum!.id,
          _currentTrack!.title,
          _currentTrack!.durationSeconds ?? 0,
        );
      }
    }
  }

  /// Indeksy utworow z plikiem — baza dla losowania.
  List<int> get _playableIndexes {
    final album = _currentAlbum;
    if (album == null) return const [];
    return [
      for (int i = 0; i < album.tracks.length; i++)
        if (album.tracks[i].hasFile) i,
    ];
  }

  Future<void> nextTrack() async {
    final album = _currentAlbum;
    if (album == null) return;

    // Reczna zmiana utworu przerywa trwajace przejscie.
    await _cancelCrossfade();

    final next = _nextIndex();
    if (next == null) {
      // Koniec albumu i brak powtarzania.
      await stopPlayback();
      return;
    }
    await playTrack(album, next);
  }


  Future<void> previousTrack() async {
    if (_currentAlbum == null) return;

    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    int prevIndex = _currentTrackIndex - 1;
    while (prevIndex >= 0) {
      if (_currentAlbum!.tracks[prevIndex].hasFile) {
        await playTrack(_currentAlbum!, prevIndex);
        return;
      }
      prevIndex--;
    }

    await _player.seek(Duration.zero);
  }

  Future<void> seekTo(Duration position) => _player.seek(position);

  Future<void> seekToPercent(double percent) async {
    final newPosition = Duration(
      milliseconds: (_duration.inMilliseconds * percent).toInt(),
    );
    await seekTo(newPosition);
  }

  Future<void> stopPlayback() async {
    await _cancelCrossfade();
    await _player.stop();
    _currentAlbum = null;
    _currentTrack = null;
    _currentTrackIndex = 0;
    _queueAlbumId = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    mediaItem.add(null);
    onChanged?.call();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    onChanged?.call();
  }

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
    onChanged?.call();
  }

  bool _autoAdvancing = false;

  Future<void> _onTrackComplete() async {
    if (_loopMode == LoopMode.one) {
      // Powtorzenie obsluguje sam AudioPlayer.
      return;
    }
    // Guard: stream stanu moze wyemitowac "completed" wielokrotnie zanim
    // nowe zrodlo sie zaladuje - nie odpalaj auto-next rownolegle.
    if (_autoAdvancing) return;
    _autoAdvancing = true;
    try {
      await nextTrack();
    } catch (e) {
      // Bez catcha jeden blad (rethrow z playTrack) zabijalby auto-next
      // na zawsze - wyjatek w listenerze streamu jest nieobslugiwany.
      debugPrint('Blad auto-next: $e');
    } finally {
      _autoAdvancing = false;
    }
  }

  void setCrossfade(bool enabled) {
    _crossfadeEnabled = enabled;
    onChanged?.call();
    unawaited(_persist((p) => p.setBool(_prefsCrossfadeEnabled, enabled)));
    if (!enabled) unawaited(_cancelCrossfade());
  }

  void setCrossfadeDuration(int seconds) {
    _crossfadeDuration = seconds.clamp(1, 10);
    onChanged?.call();
    unawaited(
        _persist((p) => p.setInt(_prefsCrossfadeDuration, _crossfadeDuration)));
  }

  Future<void> _persist(Future<void> Function(SharedPreferences) write) async {
    try {
      write(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('Zapis ustawien odtwarzania nieudany: $e');
    }
  }

  // ----- Drzewo przegladania dla Android Auto -----

  Album? _findAlbum(String id) {
    if (!Hive.isBoxOpen('albums')) return null;
    final box = Hive.box<Album>('albums');
    for (final a in box.values) {
      if (a.id == id) return a;
    }
    return null;
  }

  ({String albumId, int index})? _parseTrackId(String mediaId) {
    if (!mediaId.startsWith('track/')) return null;
    final parts = mediaId.split('/');
    if (parts.length < 3) return null;
    final index = int.tryParse(parts.last);
    if (index == null) return null;
    // Identyfikator albumu moglby teoretycznie zawierac '/', wiec sklejamy
    // wszystko pomiedzy prefiksem a indeksem.
    final albumId = parts.sublist(1, parts.length - 1).join('/');
    return (albumId: albumId, index: index);
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    if (parentMediaId == AudioService.browsableRootId) {
      if (!Hive.isBoxOpen('albums')) return [];
      final box = Hive.box<Album>('albums');
      final albums = box.values
          .where((a) => !a.isWishlist && a.tracks.any((t) => t.hasFile))
          .toList()
        ..sort((a, b) {
          final byArtist =
              a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return byArtist != 0
              ? byArtist
              : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      return [
        for (final a in albums)
          MediaItem(
            id: 'album/${a.id}',
            title: a.title,
            artist: a.artist,
            artUri: _albumArtUri(a),
            playable: false,
          ),
      ];
    }

    if (parentMediaId.startsWith('album/')) {
      final albumId = parentMediaId.substring('album/'.length);
      final album = _findAlbum(albumId);
      if (album == null) return [];
      return [
        for (int i = 0; i < album.tracks.length; i++)
          if (album.tracks[i].hasFile) _trackToMediaItem(album, i),
      ];
    }

    return [];
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final parsed = _parseTrackId(mediaId);
    if (parsed == null) return null;
    final album = _findAlbum(parsed.albumId);
    if (album == null || parsed.index >= album.tracks.length) return null;
    return _trackToMediaItem(album, parsed.index);
  }

  // ----- Overrides sesji medialnej (przyciski w aucie / na ekranie blokady) -----

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => nextTrack();

  @override
  Future<void> skipToPrevious() => previousTrack();

  @override
  Future<void> stop() async {
    await stopPlayback();
    await super.stop();
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final parsed = _parseTrackId(mediaId);
    if (parsed != null) {
      final album = _findAlbum(parsed.albumId);
      if (album != null) await playTrack(album, parsed.index);
      return;
    }
    if (mediaId.startsWith('album/')) {
      final album = _findAlbum(mediaId.substring('album/'.length));
      if (album != null) await playAlbum(album);
    }
  }

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    await _playerA.dispose();
    await _playerB.dispose();
  }
}
