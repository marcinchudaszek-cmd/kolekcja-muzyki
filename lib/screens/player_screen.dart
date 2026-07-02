import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:just_audio/just_audio.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_service.dart';
import '../models/album.dart';
import 'karaoke_screen.dart';
import 'equalizer_screen.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = Provider.of<AudioService>(context);
    final l = L.of(context);
    final album = audio.currentAlbum;
    final track = audio.currentTrack;

    if (track == null || album == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.noTrackPlaying)),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.3),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Naglowek
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      iconSize: 32,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Column(
                      children: [
                        Text(
                          l.playingFrom,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[400],
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          album.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Equalizer dostępny tylko w aplikacji mobilnej
                    if (!kIsWeb)
                      IconButton(
                        icon: const Icon(Icons.equalizer),
                        onPressed: () async {
                          Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EqualizerScreen()),
                            );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () => _showTrackOptions(context, audio),
                      ),
                  ],
                ),
              ),

              // Okladka
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildCover(context, album),
                      ),
                    ),
                  ),
                ),
              ),

              // Info o utworze
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      track.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      album.artist,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${audio.currentTrackIndex + 1} / ${album.tracks.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),

              // Slider postepu
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        inactiveTrackColor: Colors.grey[800],
                        thumbColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: Slider(
                        value: audio.progress.clamp(0.0, 1.0),
                        onChanged: (value) => audio.seekToPercent(value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AudioService.formatDuration(audio.position),
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          ),
                          Text(
                            AudioService.formatDuration(audio.duration),
                            style: TextStyle(color: Colors.grey[400], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Kontrolki
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Shuffle
                    IconButton(
                      icon: Icon(
                        Icons.shuffle,
                        color: audio.shuffle
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      onPressed: audio.toggleShuffle,
                    ),

                    // Poprzedni
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      iconSize: 40,
                      onPressed: audio.previousTrack,
                    ),

                    // Play/Pause
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: audio.isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 3,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                audio.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.black,
                              ),
                              iconSize: 40,
                              onPressed: audio.togglePlayPause,
                            ),
                    ),

                    // Nastepny
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      iconSize: 40,
                      onPressed: audio.nextTrack,
                    ),

                    // Loop
                    IconButton(
                      icon: Icon(
                        audio.loopMode == LoopMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        color: audio.loopMode != LoopMode.off
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      onPressed: audio.toggleLoopMode,
                    ),
                  ],
                ),
              ),

              // Lista utworow i Karaoke
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _showTrackList(context, audio, album),
                      icon: const Icon(Icons.queue_music),
                      label: Text(l.queueShort),
                    ),
                    const SizedBox(width: 24),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const KaraokeScreen()),
                      ),
                      icon: const Icon(Icons.mic),
                      label: const Text('Karaoke'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, Album album) {
    if (album.coverPath != null) {
      final file = File(album.coverPath!);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }

    if (album.coverUrl != null && album.coverUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: album.coverUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _buildPlaceholder(context, album),
        errorWidget: (_, __, ___) => _buildPlaceholder(context, album),
      );
    }

    return _buildPlaceholder(context, album);
  }

  Widget _buildPlaceholder(BuildContext context, Album album) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Text(
          genreEmoji(album.genre),
          style: const TextStyle(fontSize: 80),
        ),
      ),
    );
  }

  void _showTrackList(BuildContext context, AudioService audio, Album album) {
    final l = L.read(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l.trackList,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: album.tracks.length,
                itemBuilder: (context, index) {
                  final track = album.tracks[index];
                  final isPlaying = audio.currentTrackIndex == index;

                  return ListTile(
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isPlaying
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: isPlaying && audio.isPlaying
                            ? const Icon(Icons.equalizer, size: 18, color: Colors.black)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isPlaying ? Colors.black : Colors.grey,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      track.title,
                      style: TextStyle(
                        color: isPlaying ? Theme.of(context).colorScheme.primary : null,
                        fontWeight: isPlaying ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: Text(
                      track.formattedDuration,
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    onTap: track.hasFile
                        ? () async {
                            try {
                              await audio.playTrack(album, index);
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l.playbackError(e)),
                                    duration: const Duration(seconds: 10),
                                  ),
                                );
                              }
                            }
                          }
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTrackOptions(BuildContext context, AudioService audio) {
    final l = L.read(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.album),
              title: Text(l.goToAlbum),
              onTap: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(l.share),
              onTap: () {
                Navigator.pop(context);
                // TODO: Share
              },
            ),
          ],
        ),
      ),
    );
  }
}




