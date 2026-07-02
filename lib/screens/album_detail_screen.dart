import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/album.dart';
import '../services/database_service.dart';
import '../services/audio_service.dart';
import '../services/cover_service.dart';
import 'player_screen.dart';
import 'edit_album_screen.dart';

class AlbumDetailScreen extends StatefulWidget {
  final String albumId;

  const AlbumDetailScreen({super.key, required this.albumId});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final audio = Provider.of<AudioService>(context);
    final l = L.of(context);

    Album? album;
    try {
      album = db.getAlbum(widget.albumId);
    } catch (e) {
      album = null;
    }

    if (album == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l.albumNotFound)),
      );
    }
    
    final currentAlbum = album;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                currentAlbum.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                ),
              ),
              background: GestureDetector(
                onTap: () => _showCoverOptions(context, db, currentAlbum),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildCover(context, currentAlbum),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 80,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.edit, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  currentAlbum.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: currentAlbum.isFavorite ? Colors.red : null,
                ),
                onPressed: () => db.toggleFavorite(currentAlbum.id),
              ),
              PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    child: ListTile(
                      leading: Icon(
                        currentAlbum.isWishlist ? Icons.card_giftcard : Icons.card_giftcard_outlined,
                      ),
                      title: Text(currentAlbum.isWishlist ? l.removeFromWishlist : l.addToWishlist),
                    ),
                    onTap: () => db.toggleWishlist(currentAlbum.id),
                  ),
                  PopupMenuItem(
                    child: ListTile(
                      leading: const Icon(Icons.edit),
                      title: Text(l.edit),
                    ),
                    onTap: () {
                      Future.delayed(Duration.zero, () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditAlbumScreen(album: currentAlbum),
                          ),
                        );
                      });
                    },
                  ),
                  PopupMenuItem(
                    child: ListTile(
                      leading: const Icon(Icons.delete, color: Colors.red),
                      title: Text(l.delete, style: const TextStyle(color: Colors.red)),
                    ),
                    onTap: () => _confirmDelete(context, db, currentAlbum),
                  ),
                ],
              ),
            ],
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentAlbum.artist,
                    style: TextStyle(
                      fontSize: 20,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      if (currentAlbum.year != null)
                        _buildChip(context, Icons.calendar_today, '${currentAlbum.year}'),
                      _buildChip(context, Icons.music_note, l.tracksCount(currentAlbum.tracks.length)),
                      _buildChip(context, Icons.timer, currentAlbum.formattedDuration),
                      _buildChip(context, null, '${genreEmoji(currentAlbum.genre)} ${l.genreName(currentAlbum.genre)}'),
                      _buildChip(context, Icons.album, _formatLabel(l, currentAlbum.format)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Text(l.ratingLabel),
                      ...List.generate(5, (i) => GestureDetector(
                        onTap: () => db.setRating(currentAlbum.id, i + 1),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            i < currentAlbum.rating ? Icons.star : Icons.star_border,
                            color: i < currentAlbum.rating ? Colors.amber : Colors.grey,
                            size: 28,
                          ),
                        ),
                      )),
                    ],
                  ),
                  
                  if (currentAlbum.notes != null && currentAlbum.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notes, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(currentAlbum.notes!)),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  
                  Text(
                    l.listenOnline,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openSpotify(currentAlbum.artist, currentAlbum.title),
                          icon: const Icon(Icons.music_note, color: Color(0xFF1DB954)),
                          label: const Text('Spotify'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openYouTubeMusic(currentAlbum.artist, currentAlbum.title),
                          icon: const Icon(Icons.play_circle, color: Colors.red),
                          label: const Text('YT Music'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openYouTube(currentAlbum.artist, currentAlbum.title),
                      icon: const Icon(Icons.ondemand_video, color: Colors.red),
                      label: Text(l.searchYouTube),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  if (currentAlbum.tracks.any((t) => t.hasFile))
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await audio.playAlbum(currentAlbum);
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const PlayerScreen()),
                              );
                            }
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
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l.playAlbum),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  Row(
                    children: [
                      Text(
                        l.trackList,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        l.tracksAvailable(
                          currentAlbum.tracks.where((t) => t.hasFile).length,
                          currentAlbum.tracks.length,
                        ),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = currentAlbum.tracks[index];
                final isPlaying = audio.currentAlbum?.id == currentAlbum.id &&
                                  audio.currentTrackIndex == index;
                
                return ListTile(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: isPlaying && audio.isPlaying
                          ? const Icon(Icons.equalizer, size: 18, color: Colors.black)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isPlaying ? Colors.black : Colors.grey,
                                fontWeight: isPlaying ? FontWeight.bold : null,
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (track.formattedDuration.isNotEmpty)
                        Text(
                          track.formattedDuration,
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        track.hasFile ? Icons.play_circle : Icons.music_off,
                        color: track.hasFile
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[600],
                        size: 24,
                      ),
                    ],
                  ),
                  onTap: track.hasFile
                      ? () async {
                          try {
                            await audio.playTrack(currentAlbum, index);
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const PlayerScreen()),
                              );
                            }
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
              childCount: currentAlbum.tracks.length,
            ),
          ),
          
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
        ],
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

  Widget _buildChip(BuildContext context, IconData? icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.grey[400]),
            const SizedBox(width: 4),
          ],
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _formatLabel(L l, String format) {
    switch (format) {
      case 'cd': return 'CD';
      case 'vinyl': return l.formatVinyl;
      case 'digital': return l.formatDigital;
      case 'cassette': return l.formatCassette;
      default: return format;
    }
  }

  void _confirmDelete(BuildContext context, DatabaseService db, Album album) {
    final l = L.read(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteAlbumTitle),
        content: Text(l.deleteAlbumConfirm(album.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () {
              db.deleteAlbum(album.id);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: Text(l.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openSpotify(String artist, String title) async {
    final query = Uri.encodeComponent('$artist $title');
    final url = 'https://open.spotify.com/search/$query';
    await _launchUrl(url);
  }

  void _openYouTubeMusic(String artist, String title) async {
    final query = Uri.encodeComponent('$artist $title');
    final url = 'https://music.youtube.com/search?q=$query';
    await _launchUrl(url);
  }

  void _openYouTube(String artist, String title) async {
    final query = Uri.encodeComponent('$artist $title full album');
    final url = 'https://www.youtube.com/results?search_query=$query';
    await _launchUrl(url);
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showCoverOptions(BuildContext context, DatabaseService db, Album album) {
    final parentContext = context;
    final l = L.read(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.changeCover,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.search),
              title: Text(l.searchAuto),
              subtitle: Text(l.searchAutoSub),
              onTap: () {
                  Navigator.pop(parentContext);
                  _searchCover(parentContext, db, album);
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view),
              title: Text(l.chooseSuggestion),
              subtitle: Text(l.chooseSuggestionSub),
              onTap: () {
                  Navigator.pop(parentContext);
                  _showCoverSuggestions(parentContext, db, album);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(l.pasteUrl),
              subtitle: Text(l.pasteUrlSub),
              onTap: () {
                  Navigator.pop(parentContext);
                  _enterCoverUrl(parentContext, db, album);
              },
            ),
            if (album.coverUrl != null && album.coverUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(l.removeCover, style: const TextStyle(color: Colors.red)),
                onTap: () {
                  db.updateCover(album.id, '');
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.coverRemoved)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _searchCover(BuildContext context, DatabaseService db, Album album) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l = L.read(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l.searchingCover),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final coverUrl = await CoverService.fetchCover(album.artist, album.title);
      
      if (!mounted) return;
      navigator.pop();
      
      if (coverUrl != null && coverUrl.isNotEmpty) {
        db.updateCover(album.id, coverUrl);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(l.coverUpdated),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(l.coverNotFound),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l.errorGeneric(e)), backgroundColor: Colors.red),
      );
    }
  }

  void _showCoverSuggestions(BuildContext context, DatabaseService db, Album album) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final theme = Theme.of(context);
    final l = L.read(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l.loadingSuggestions),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final suggestions = await CoverService.fetchSuggestions(album.artist, album.title);
      
      if (!mounted) return;
      navigator.pop();
      
      if (suggestions.isEmpty) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l.noSuggestions)),
        );
        return;
      }

      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        backgroundColor: theme.colorScheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Column(
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
                  l.chooseCover,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: suggestions.length,
                  itemBuilder: (gridContext, index) {
                    final suggestion = suggestions[index];
                    return GestureDetector(
                      onTap: () {
                        db.updateCover(album.id, suggestion.url);
                        Navigator.pop(sheetContext);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(l.coverChanged),
                            backgroundColor: Colors.green,
                          ),
                        );
                        setState(() {});
                      },
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Image.network(
                                suggestion.url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image, size: 48),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    suggestion.album,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    suggestion.artist,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    suggestion.source,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l.errorGeneric(e)), backgroundColor: Colors.red),
      );
    }
  }

  void _enterCoverUrl(BuildContext context, DatabaseService db, Album album) {
    final controller = TextEditingController(text: album.coverUrl ?? '');
    final l = L.read(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.pasteCoverUrl),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty && url.startsWith('http')) {
                db.updateCover(album.id, url);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l.coverChanged),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(l.save),
          ),
        ],
      ),
    );
  }
}


