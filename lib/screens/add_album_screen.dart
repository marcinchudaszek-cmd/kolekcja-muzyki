import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dodaj album'),
        actions: [
          TextButton(
            onPressed: _saveAlbum,
            child: const Text('Zapisz'),
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
              decoration: const InputDecoration(
                labelText: 'Artysta *',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Podaj artyste';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Tytul
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Tytul albumu *',
                prefixIcon: Icon(Icons.album),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Podaj tytul';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Rok
            TextFormField(
              controller: _yearController,
              decoration: const InputDecoration(
                labelText: 'Rok wydania',
                prefixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            // Gatunek
            Text(
              'Gatunek',
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
              'Format',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ('cd', 'ðŸ’¿ CD'),
                ('vinyl', 'ðŸ“€ Winyl'),
                ('digital', 'â˜ï¸ Cyfrowy'),
                ('cassette', 'ðŸ“¼ Kaseta'),
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
              'Ocena',
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
              decoration: const InputDecoration(
                labelText: 'Notatki',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
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
                label: const Text('Zapisz album'),
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

    final db = Provider.of<DatabaseService>(context, listen: false);
    final artist = _artistController.text.trim();
    final title = _titleController.text.trim();
    
    // Sprawdz duplikaty
    if (db.isDuplicate(artist, title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('âš ï¸ Ten album juz istnieje w kolekcji!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Pokaz ladowanie
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Pobieram okladke...'),
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
          content: Text('OK Album dodany!${coverUrl != null ? ' (z okladka)' : ''}'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('âš ï¸ Ten album juz istnieje!'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
