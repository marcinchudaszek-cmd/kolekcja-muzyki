import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/album.dart';
import '../services/cover_service.dart';
import '../services/database_service.dart';
import 'album_detail_screen.dart';

/// Przeglad okladek calej kolekcji: sprawdza kazda okladke z internetu,
/// wykrywa nietrafione i proponuje pasujace. Nic nie zmienia bez akceptacji —
/// propozycje sa domyslnie zaznaczone, jedno dotkniecie je zapisuje.
class CoverReviewScreen extends StatefulWidget {
  const CoverReviewScreen({super.key});

  @override
  State<CoverReviewScreen> createState() => _CoverReviewScreenState();
}

class _Proposal {
  _Proposal(this.album, this.check);
  final Album album;
  final CoverCheck check;
  bool selected = true;
}

class _CoverReviewScreenState extends State<CoverReviewScreen> {
  final List<_Proposal> _replace = [];
  final List<_Proposal> _add = [];
  final List<Album> _unconfirmed = [];
  int _ok = 0;
  int _manual = 0;
  int _notFound = 0;
  int _done = 0;
  int _total = 0;
  bool _running = true;
  bool _stopRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _stopRequested = true;
    super.dispose();
  }

  Future<void> _run() async {
    final db = Provider.of<DatabaseService>(context, listen: false);
    final manual = await CoverService.manualIds();
    // Wlasne zdjecia okladek (coverPath) i okladki wybrane recznie zostaja.
    final albums = db.allAlbums
        .where((a) => a.coverPath == null || a.coverPath!.isEmpty)
        .toList();
    final toCheck = <Album>[];
    for (final a in albums) {
      if (manual.contains(a.id)) {
        _manual++;
      } else {
        toCheck.add(a);
      }
    }
    if (!mounted) return;
    setState(() => _total = toCheck.length);

    for (final album in toCheck) {
      if (_stopRequested || !mounted) break;
      try {
        final check = await CoverService.checkCover(
          album.artist,
          album.title,
          currentUrl: album.coverUrl,
          trackCount: album.tracks.isEmpty ? null : album.tracks.length,
        );
        if (!mounted) return;
        setState(() {
          switch (check.verdict) {
            case CoverVerdict.ok:
              _ok++;
            case CoverVerdict.replace:
              _replace.add(_Proposal(album, check));
            case CoverVerdict.add:
              _add.add(_Proposal(album, check));
            case CoverVerdict.unconfirmed:
              _unconfirmed.add(album);
            case CoverVerdict.notFound:
              _notFound++;
          }
        });
      } catch (e) {
        debugPrint('Przeglad okladki ${album.artist} - ${album.title}: $e');
      }
      if (mounted) setState(() => _done++);
    }
    if (mounted) setState(() => _running = false);
  }

  int get _selectedCount =>
      [..._replace, ..._add].where((p) => p.selected).length;

  Future<void> _apply() async {
    final l = L.read(context);
    final db = Provider.of<DatabaseService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final chosen = [..._replace, ..._add].where((p) => p.selected).toList();
    for (final p in chosen) {
      await db.updateCover(p.album.id, p.check.newUrl!);
    }
    if (!mounted) return;
    setState(() {
      _replace.removeWhere((p) => p.selected);
      _add.removeWhere((p) => p.selected);
      _ok += chosen.length;
    });
    messenger.showSnackBar(SnackBar(
      content: Text(l.coversApplied(chosen.length)),
      backgroundColor: Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);
    final nothingToDo = !_running &&
        _replace.isEmpty &&
        _add.isEmpty &&
        _unconfirmed.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l.coverReviewTitle)),
      body: Column(
        children: [
          if (_running)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(l.checkingCovers(_done, _total))),
                      TextButton(
                        onPressed: _stopRequested
                            ? null
                            : () => setState(() => _stopRequested = true),
                        child: Text(l.stopChecking),
                      ),
                    ],
                  ),
                  LinearProgressIndicator(
                    value: _total == 0 ? null : _done / _total,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l.coversSummary(_ok, _manual, _notFound),
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
          if (nothingToDo)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.noCoverIssues, textAlign: TextAlign.center),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (_replace.isNotEmpty) ...[
                    _header(theme, l.coversToReplace(_replace.length)),
                    for (final p in _replace) _proposalTile(p, l),
                  ],
                  if (_add.isNotEmpty) ...[
                    _header(theme, l.coversToAdd(_add.length)),
                    for (final p in _add) _proposalTile(p, l),
                  ],
                  if (_unconfirmed.isNotEmpty) ...[
                    _header(theme, l.coversUnconfirmed(_unconfirmed.length)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        l.coversUnconfirmedHint,
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ),
                    for (final a in _unconfirmed) _unconfirmedTile(a),
                  ],
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: _selectedCount == 0
          ? null
          : FloatingActionButton.extended(
              onPressed: _apply,
              icon: const Icon(Icons.check),
              label: Text(l.applySelectedCovers(_selectedCount)),
            ),
    );
  }

  Widget _header(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text,
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _thumb(String? url) {
    const size = 56.0;
    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: Colors.white10,
        child: const Icon(Icons.album, color: Colors.white38),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.white10,
          child: const Icon(Icons.broken_image, color: Colors.white38),
        ),
      ),
    );
  }

  Widget _proposalTile(_Proposal p, L l) {
    final c = p.check;
    return CheckboxListTile(
      value: p.selected,
      onChanged: (v) => setState(() => p.selected = v ?? false),
      secondary: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.album.coverUrl != null && p.album.coverUrl!.isNotEmpty) ...[
            _thumb(p.album.coverUrl),
            const Icon(Icons.arrow_forward, size: 16),
          ],
          _thumb(c.newUrl),
        ],
      ),
      title: Text(
        '${p.album.artist} – ${p.album.title}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l.coverFoundAs(c.source ?? '', c.matchArtist ?? '', c.matchAlbum ?? ''),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _unconfirmedTile(Album a) => ListTile(
        leading: _thumb(a.coverUrl),
        title: Text('${a.artist} – ${a.title}',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AlbumDetailScreen(albumId: a.id)),
          );
          // Uzytkownik mogl wybrac okladke — zdejmij album z listy.
          final manual = await CoverService.manualIds();
          if (mounted && manual.contains(a.id)) {
            setState(() {
              _unconfirmed.remove(a);
              _manual++;
            });
          }
        },
      );
}
