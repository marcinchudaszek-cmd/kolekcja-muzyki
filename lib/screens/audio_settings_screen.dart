import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/audio_service.dart';

class AudioSettingsScreen extends StatelessWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia dzwieku'),
      ),
      body: Consumer<AudioService>(
        builder: (context, audio, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader(context, 'Plynne przejscia (Crossfade)'),
              
              SwitchListTile(
                title: const Text('Wlacz crossfade'),
                subtitle: const Text('Plynne przejscie miedzy utworami'),
                value: audio.crossfadeEnabled,
                onChanged: (value) => audio.setCrossfade(value),
              ),
              
              if (audio.crossfadeEnabled) ...[
                ListTile(
                  title: const Text('Czas przejscia'),
                  subtitle: Text('${audio.crossfadeDuration} sekund'),
                  trailing: SizedBox(
                    width: 150,
                    child: Slider(
                      value: audio.crossfadeDuration.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${audio.crossfadeDuration}s',
                      onChanged: (value) => audio.setCrossfadeDuration(value.toInt()),
                    ),
                  ),
                ),
              ],
              
              const Divider(height: 32),
              
              _buildSectionHeader(context, 'Equalizer'),
              
              ListTile(
                leading: const Icon(Icons.equalizer),
                title: const Text('Otworz systemowy equalizer'),
                subtitle: const Text('Dostosuj tony niskie i wysokie'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openSystemEqualizer(context),
              ),
              
              const Divider(height: 32),
              
              _buildSectionHeader(context, 'Informacje'),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '• Crossfade tworzy plynne przejscie miedzy utworami\n\n'
                    '• Equalizer systemowy pozwala dostosowac czestotliwosci dla wszystkich aplikacji',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  void _openSystemEqualizer(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Equalizer'),
        content: const Text(
          'Aby otworzyc equalizer:\n\n'
          '1. Otworz Ustawienia telefonu\n'
          '2. Przejdz do: Dzwiek i wibracje\n'
          '3. Znajdz: Jakosc dzwieku / Equalizer\n\n'
          'Lub pobierz aplikacje Equalizer ze Sklepu Play.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final url = Uri.parse('https://play.google.com/store/search?q=equalizer&c=apps');
              await launchUrl(url, mode: LaunchMode.externalApplication);
            },
            child: const Text('Sklep Play'),
          ),
        ],
      ),
    );
  }
}
