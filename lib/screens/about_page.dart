import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('À propos', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Color(0xFFFF6B35)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(children: [
              const SizedBox(height: 8),
              Image.asset('assets/logo.png', height: 72),
              const SizedBox(height: 12),
              const Text('OrignalScan',
                  style: TextStyle(color: Colors.white, fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const Text('Habitat orignal — Québec',
                  style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
              const SizedBox(height: 24),
            ]),
          ),
          _card(children: [
            _title('Analyse écoforestière'),
            const SizedBox(height: 8),
            const Text(
              'OrignalScan analyse les données écoforestières du Québec (IEQM) pour identifier les meilleurs habitats d\'orignal selon les critères scientifiques :\n\n• Couverture végétale (forêt mixte, résineux)\n• Espèces dominantes (peuplier, aulne, saule)\n• Âge du peuplement\n• Classe de drainage\n• Proximité des cours d\'eau',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
            ),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Données écoforestières'),
            const SizedBox(height: 8),
            const Text(
              'Données écoforestières fournies par le Ministère des Ressources naturelles et des Forêts (MRNF), diffusées sur Données Québec.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
            ),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Nous suivre'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => launchUrl(
                Uri.parse('https://www.facebook.com/profile.php?id=61588826944605'),
                mode: LaunchMode.externalApplication,
              ),
              child: Row(children: [
                const Icon(Icons.facebook, color: Color(0xFF1877F2), size: 28),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Page Facebook OrignalScan',
                        style: TextStyle(color: Color(0xFF1877F2), fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    Text('Suivez-nous pour les dernières nouvelles',
                        style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
                ),
                const Icon(Icons.open_in_new, color: Colors.white38, size: 16),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Score d\'habitat'),
            const SizedBox(height: 8),
            _scoreRow('18+', 'Excellent', const Color(0xFF1A3A08)),
            _scoreRow('13–17', 'Très bon', const Color(0xFF2D5016)),
            _scoreRow('8–12', 'Bon', const Color(0xFF5A8A1E)),
            _scoreRow('4–7', 'Moyen', const Color(0xFF8B7355)),
          ]),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _title(String text) => Text(text,
      style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 13,
          fontWeight: FontWeight.bold, letterSpacing: 0.5));

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12,
            fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _scoreRow(String score, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(width: 16, height: 16,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Text(score, style: const TextStyle(color: Colors.white70, fontSize: 12,
            fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
