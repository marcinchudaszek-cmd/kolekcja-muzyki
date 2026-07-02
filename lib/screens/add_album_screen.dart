import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/album.dart';
import '../services/database_service.dart';
import '../services/cover_service.dart';

class AddAlbumScreen extends StatefulWidget {
  const AddAlbumScreen({super.key});

  @override
  State<AddAlbumScreen> createState() => _AddAlbumScreenState();
}

class _AddAlbumScreenState extends State<AddAlbumScreen> {
  final _formKey = GlobalKey<FormState>();
  final _artistController = TextEditingController();
  final _titleController = TextEditingController();
  final _yearController = TextEditingController();
  final _notesController = TextEditingController();
  
  String _genre = 'other';
  String _format = 'cd';
  int _rating = 3;

  @override
  void dispose() {
    _artistController.dispose();
    _titleController.dispose();
    _yearController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.addAlbumTitle),
        actions: [
          TextButton(
            onPressed: _saveAlbum,
            child: Text(l.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Artysta
            TextFormField(
              controller: _artistController,
              decoration: InputDecoration(
                labelText: '${l.fieldArtist} *',
                prefixIcon: const Icon(Icons.person),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.enterArtist;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Tytul
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '${l.albumTitleLabel} *',
                prefixIcon: const Icon(Icons.album),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.enterTitle;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Rok
            TextFormField(
              controller: _yearController,
              decoration: InputDecoration(
                labelText: l.releaseYear,
                prefixIcon: const Icon(Icons.calendar_today),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            // Gatunek
            Text(
              l.fieldGenre,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'rock', 'pop', 'metal', 'jazz', 'classical', 'electronic', 
                'hip-hop', 'blues', 'other'
              ].map((g) => ChoiceChip(
                label: Text('${genreEmoji(g)} ${genreName(g)}'),
                selected: _genre == g,
                onSelected: (selected) {
                  if (selected) setState(() => _genre = g);
                },
              )).toList(),
            ),
            const SizedBox(height: 24),

            // Format
            Text(
              l.fieldFormat,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ('cd', '💿 CD'),
                ('vinyl', '📀 ${l.formatVinyl}'),
                ('digital', '☁️ ${l.formatDigital}'),
                ('cassette', '📼 ${l.formatCassette}'),
              ].map((f) => ChoiceChip(
                label: Text(f.$2),
                selected: _format == f.$1,
                onSelected: (selected) {
                  if (selected) setState(() => _format = f.$1);
                },
              )).toList(),
            ),
            const SizedBox(height: 24),

            // Ocena
            Text(
              l.rating,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => IconButton(
                icon: Icon(
                  i < _rating ? Icons.star : Icons.star_border,
                  color: i < _rating ? Colors.amber : Colors.grey,
                ),
                iconSize: 40,
                onPressed: () => setState(() => _rating = i + 1),
              )),
            ),
            const SizedBox(height: 24),

            // Notatki
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: l.notes,
                prefixIcon: const Icon(Icons.notes),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),

            // Przycisk zapisz
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveAlbum,
                icon: const Icon(Icons.save),
                label: Text(l.saveAlbum),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveAlbum() async {
    if (!_formKey.currentState!.validate()) return;
    final l = L.read(context);

    final db = Provider.of<DatabaseService>(context, listen: false);
    final artist = _artistController.text.trim();
    final title = _titleController.text.trim();
    
    // Sprawdz duplikaty
    if (db.isDuplicate(artist, title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.albumExists),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Pokaz ladowanie
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
                Text(l.downloadingCover),
              ],
            ),
          ),
        ),
      ),
    );

    // Pobierz okladke
    String? coverUrl;
    try {
      coverUrl = await CoverService.fetchCover(artist, title);
    } catch (e) {
      print('Blad pobierania okladki: $e');
    }

    if (!mounted) return;
    Navigator.pop(context); // Zamknij dialog ladowania
    
    final album = Album(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      artist: artist,
      title: title,
      year: int.tryParse(_yearController.text),
      genre: _genre,
      format: _format,
      rating: _rating,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      coverUrl: coverUrl,
    );

    final added = await db.addAlbum(album);
    
    if (added) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.albumAddedMsg(coverUrl != null)),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.albumExists),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
