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
              ColorFiltered(
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                child: Image.asset('assets/logo.png', height: 72),
              ),
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
            _title('Méthodologie de l\'habitat'),
            const SizedBox(height: 8),
            const Text(
              'L\'algorithme de scoring est basé sur les principes de l\'écologie de l\'orignal documentés par le MRNF et les universités québécoises (UQAR, UQAM) :\n\n'
              '• Alimentation — L\'orignal est un herbivore brouteur. Il préfère les jeunes peuplements feuillus (peuplier faux-tremble, aulne rugueux, saule, bouleau à papier) qui poussent dans les coupes et brûlis récents (5–25 ans).\n\n'
              '• Abri — Les résineux denses (épinette, sapin) servent de protection thermique en hiver et de couvert de sécurité.\n\n'
              '• Eau — L\'orignal est étroitement lié aux milieux riverains, marécages et tourbières pour la végétation aquatique (été) et la thermorégulation.\n\n'
              '• Transitions — Les zones de transition entre feuillu et résineux concentrent l\'activité : nourriture et abri à portée.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
            ),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Sources scientifiques'),
            const SizedBox(height: 8),
            const Text(
              '• Courtois R., Dussault C. et al. — Sélection d\'habitat de l\'orignal en forêt boréale aménagée, UQAR / MFFP.\n\n'
              '• Dussault C. et al. (2005) — Linking moose habitat selection to limiting factors. Ecography 28.\n\n'
              '• Ouellet J.-P. et al. — Études sur l\'orignal au Québec, Université de Moncton.\n\n'
              '• MRNF Québec — Données IEQM (Inventaire Écoforestier du Québec Méridional), diffusées sur Données Québec.\n\n'
              '📋 Données écoforestières © Gouvernement du Québec (MFFP) — Reproduit avec la permission du ministère des Forêts, de la Faune et des Parcs du Québec. Licence : Données Québec (CC BY 4.0).',
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
            _title('Légende des couleurs'),
            const SizedBox(height: 8),
            _scoreRow('Blanc', 'Coupe / Régénération — meilleure nourriture', Colors.white),
            const SizedBox(height: 2),
            _scoreRow('Bleu', 'Riverain / Marécageux — eau et végétation aquatique', Color(0xFF1565C0)),
            const SizedBox(height: 2),
            _scoreRow('Jaune', 'Feuillu — alimentation (peuplier, bouleau, érable)', Color(0xFFFFD600)),
            const SizedBox(height: 2),
            _scoreRow('Orange', 'Mixte — transition nourriture + abri', Color(0xFFFF6D00)),
            const SizedBox(height: 2),
            _scoreRow('Vert', 'Résineux — abri et couvert hivernal', Color(0xFF1B5E20)),
            const SizedBox(height: 8),
            const Text(
              'L\'opacité de chaque couleur augmente avec le score orignal — plus c\'est opaque, meilleur est l\'habitat.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
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
