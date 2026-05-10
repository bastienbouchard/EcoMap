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
            _title('Fonctions principales'),
            const SizedBox(height: 8),
            _item('🔥 Hot', 'Affiche les 5 meilleurs habitats d\'orignal dans la zone visible.'),
            _item('🗺 Parcours', 'Génère un itinéraire optimisé selon le vent et les points chauds.'),
            _item('👥 Groupe', 'Partage ta position GPS avec les autres chasseurs du même code.'),
            _item('⏺ Suivi', 'Enregistre ton déplacement GPS. Appuie sur ■ pour arrêter.'),
            _item('📍 Obs.', 'Ajoute une observation terrain au centre de l\'écran.'),
            _item('🏕 Affût', 'Corridors naturels où l\'orignal est forcé de passer — rayon 3 km.'),
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
