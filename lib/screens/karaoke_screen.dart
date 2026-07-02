import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_service.dart';
import '../services/lyrics_service.dart';

class KaraokeScreen extends StatefulWidget {
  const KaraokeScreen({super.key});

  @override
  State<KaraokeScreen> createState() => _KaraokeScreenState();
}

class _KaraokeScreenState extends State<KaraokeScreen> {
  List<LyricLine>? _lyrics;
  bool _isLoading = true;
  String? _error;
  String _lastTrack = '';

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    final audio = Provider.of<AudioService>(context, listen: false);
    final l = L.read(context);

    if (audio.currentAlbum == null || audio.currentTrackIndex < 0) {
      setState(() {
        _error = l.noTrackPlaying;
        _isLoading = false;
      });
      return;
    }

    final track = audio.currentAlbum!.tracks[audio.currentTrackIndex];
    final trackKey = '${audio.currentAlbum!.artist}-${track.title}';
    
    // Nie laduj ponownie jesli to ten sam utwor
    if (trackKey == _lastTrack && _lyrics != null) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    _lastTrack = trackKey;
    
    try {
      final lyrics = await LyricsService.fetchSyncedLyrics(
        audio.currentAlbum!.artist,
        track.title,
      );
      
      if (mounted) {
        setState(() {
          _lyrics = lyrics;
          _isLoading = false;
          if (lyrics == null || lyrics.isEmpty) {
            _error = l.noLyricsFor(track.title);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = l.lyricsError;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioService>(
      builder: (context, audio, child) {
        // Sprawdz czy zmienil sie utwor
        if (audio.currentAlbum != null && audio.currentTrackIndex >= 0) {
          final track = audio.currentAlbum!.tracks[audio.currentTrackIndex];
          final trackKey = '${audio.currentAlbum!.artist}-${track.title}';
          if (trackKey != _lastTrack) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadLyrics());
          }
        }

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  audio.currentAlbum?.tracks[audio.currentTrackIndex].title ?? 'Karaoke',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  audio.currentAlbum?.artist ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  _lastTrack = '';
                  _loadLyrics();
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Tekst piosenki
              Expanded(
                child: _buildLyricsView(audio),
              ),
              
              // Kontrolki odtwarzania
              _buildControls(audio),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLyricsView(AudioService audio) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              L.of(context).searchingLyrics,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.music_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  _lastTrack = '';
                  _loadLyrics();
                },
                icon: const Icon(Icons.refresh),
                label: Text(L.of(context).tryAgain),
              ),
            ],
          ),
        ),
      );
    }

    if (_lyrics == null || _lyrics!.isEmpty) {
      return Center(
        child: Text(
          L.of(context).noLyrics,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    // Sprawdz czy mamy zsynchronizowane teksty
    final hasSyncedLyrics = _lyrics!.any((l) => l.isSynced);
    
    if (hasSyncedLyrics) {
      return _buildSyncedLyrics(audio);
    } else {
      return _buildStaticLyrics();
    }
  }

  Widget _buildSyncedLyrics(AudioService audio) {
    final currentPosition = audio.position;
    int currentLineIndex = 0;
    
    // Znajdz aktualna linie
    for (int i = 0; i < _lyrics!.length; i++) {
      if (_lyrics![i].time != null && _lyrics![i].time! <= currentPosition) {
        currentLineIndex = i;
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _lyrics!.length,
      itemBuilder: (context, index) {
        final line = _lyrics![index];
        final isCurrentLine = index == currentLineIndex;
        final isPastLine = index < currentLineIndex;
        
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: isCurrentLine ? 24 : 18,
              fontWeight: isCurrentLine ? FontWeight.bold : FontWeight.normal,
              color: isCurrentLine 
                  ? Colors.white 
                  : isPastLine 
                      ? Colors.grey[600] 
                      : Colors.grey[400],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
            child: Text(line.text),
          ),
        );
      },
    );
  }

  Widget _buildStaticLyrics() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: _lyrics!.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            _lyrics![index].text,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  Widget _buildControls(AudioService audio) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.8),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pasek postepu
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: audio.position.inMilliseconds.toDouble(),
                max: audio.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                activeColor: Colors.white,
                inactiveColor: Colors.grey[800],
                onChanged: (value) {
                  audio.seekTo(Duration(milliseconds: value.toInt()));
                },
              ),
            ),
            
            // Czas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(audio.position),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                  Text(
                    _formatDuration(audio.duration),
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Przyciski
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  iconSize: 36,
                  onPressed: audio.previousTrack,
                ),
                const SizedBox(width: 16),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      audio.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                    ),
                    iconSize: 40,
                    onPressed: audio.togglePlayPause,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  iconSize: 36,
                  onPressed: audio.nextTrack,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
