import 'package:flutter/material.dart';

class AidePage extends StatelessWidget {
  const AidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Aide', style: TextStyle(color: Colors.white)),
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFFF6B35)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(children: [
            _title('Légende des couleurs'),
            const SizedBox(height: 8),
            _scoreRow('Blanc', 'Coupe / Régénération — meilleure nourriture', Colors.white),
            const SizedBox(height: 2),
            _scoreRow('Bleu', 'Riverain / Marécageux — eau et végétation aquatique', const Color(0xFF1565C0)),
            const SizedBox(height: 2),
            _scoreRow('Jaune', 'Feuillu — alimentation (peuplier, bouleau, érable)', const Color(0xFFFFD600)),
            const SizedBox(height: 2),
            _scoreRow('Orange', 'Mixte — transition nourriture + abri', const Color(0xFFFF6D00)),
            const SizedBox(height: 2),
            _scoreRow('Vert', 'Résineux — abri et couvert automnal', const Color(0xFF1B5E20)),
            const SizedBox(height: 8),
            const Text(
              'L\'opacité de chaque couleur augmente avec le score orignal — plus c\'est opaque, meilleur est l\'habitat.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Codes de peuplement'),
            const SizedBox(height: 6),
            _note('Les étiquettes affichent : dominante + sous-dominante + âge + densité\nEx: SAEP60C = Sapin, Épinette, 60 ans, semi-dense'),
            const SizedBox(height: 10),
            _title('Essences'),
            const SizedBox(height: 4),
            _row('PE', 'Peuplier tremblant'),
            _row('AU', 'Aulne'),
            _row('SA', 'Sapin baumier'),
            _row('BP', 'Bouleau à papier'),
            _row('ERR', 'Érable rouge'),
            _row('BJ', 'Bouleau jaune'),
            _row('EN', 'Épinette noire'),
            _row('EB', 'Épinette blanche'),
            _row('EP', 'Épinette (groupe)'),
            _row('MEL', 'Mélèze laricin'),
            _row('ERS', 'Érable à sucre'),
            _row('TH', 'Thuya (cèdre)'),
            _row('PIB', 'Pin blanc'),
            _row('PIR', 'Pin rouge'),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Classes d\'âge'),
            const SizedBox(height: 4),
            _row('J / JIN', 'Jeune — moins de 10 ans'),
            _row('10', '10 à 20 ans'),
            _row('20', '20 à 30 ans'),
            _row('30', '30 à 40 ans'),
            _row('40', '40 à 50 ans'),
            _row('50', '50 à 60 ans'),
            _row('60', '60 à 80 ans'),
            _row('80', '80 à 100 ans'),
            _row('100 / VIN', 'Plus de 100 ans'),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Densité'),
            const SizedBox(height: 4),
            _row('A', 'Éparse (< 25%)'),
            _row('B', 'Clairsemée (25–40%)'),
            _row('C', 'Semi-dense (40–60%)'),
            _row('D', 'Dense (60–80%)'),
          ]),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF2D2D2D),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _title(String t) => Text(t,
      style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 13,
          fontWeight: FontWeight.bold, letterSpacing: 0.5));

  Widget _note(String t) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.5)),
  );

  Widget _item(String label, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: RichText(
      text: TextSpan(children: [
        TextSpan(text: '$label  ',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        TextSpan(text: desc,
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
      ]),
    ),
  );

  Widget _scoreRow(String score, String label, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Container(width: 16, height: 16,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 10),
      Text(score, style: const TextStyle(color: Colors.white70, fontSize: 12,
          fontWeight: FontWeight.bold)),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))),
    ]),
  );

  Widget _row(String code, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(width: 56,
          child: Text(code, style: const TextStyle(color: Colors.white, fontSize: 11,
              fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
      Expanded(child: Text(desc,
          style: const TextStyle(color: Colors.white60, fontSize: 11))),
    ]),
  );
}
