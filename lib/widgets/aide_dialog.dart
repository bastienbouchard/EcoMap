import 'package:flutter/material.dart';

class AideItem extends StatelessWidget {
  final String title;
  final String desc;
  const AideItem(this.title, this.desc, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$title  ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            TextSpan(text: desc, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

Widget _sectionTitle(String t) => Text(t,
    style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 12, fontWeight: FontWeight.bold));

Widget _glossaireNote(String t) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11)));

Widget _glossRow(String code, String desc) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(children: [
      SizedBox(width: 46,
        child: Text(code, style: const TextStyle(color: Colors.white, fontSize: 11,
            fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
      Expanded(child: Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 11))),
    ]));

void showAideDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF2D2D2D),
      title: Row(children: [
        const Expanded(child: Text('Aide', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
        IconButton(
          icon: const Icon(Icons.close, color: Color(0xFFFF6B35), size: 20),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ]),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const AideItem('🔥 Spots', 'Affiche les 5 meilleurs habitats d\'orignal dans la zone visible.'),
            const AideItem('🗺 Parcours', 'Génère un itinéraire optimisé selon le vent et les points chauds.'),
            const AideItem('👥 Groupe', 'Partage ta position GPS avec les autres chasseurs du même code.'),
            const AideItem('⏺ Tracé', 'Enregistre ton déplacement GPS. Appuie sur Stop pour sauvegarder.'),
            const AideItem('! Obs.', 'Ajoute une observation terrain au centre de l\'écran.'),
            const AideItem('🏕 Affût', 'Corridors naturels où l\'orignal est forcé de passer — rayon 3 km.'),
            const SizedBox(height: 14),
            _sectionTitle('Codes de peuplement'),
            const SizedBox(height: 6),
            _glossaireNote('Les étiquettes sur la carte affichent : dominante + sous-dominante + âge + densité\nEx: SAEP60C = Sapin (dominant), Épinette (sous-dominant), 60 ans, semi-dense'),
            const SizedBox(height: 8),
            _sectionTitle('Essences (2 premières lettres = dominante, 2 suivantes = sous-dominante)'),
            const SizedBox(height: 4),
            _glossRow('PE', 'Peuplier tremblant'),
            _glossRow('AU', 'Aulne'),
            _glossRow('SA', 'Sapin baumier'),
            _glossRow('BP', 'Bouleau à papier'),
            _glossRow('ERR', 'Érable rouge'),
            _glossRow('BJ', 'Bouleau jaune'),
            _glossRow('EN', 'Épinette noire'),
            _glossRow('EB', 'Épinette blanche'),
            _glossRow('EP', 'Épinette (groupe)'),
            _glossRow('MEL', 'Mélèze laricin'),
            _glossRow('ERS', 'Érable à sucre'),
            _glossRow('TH', 'Thuya (cèdre)'),
            _glossRow('PIB', 'Pin blanc'),
            _glossRow('PIR', 'Pin rouge'),
            const SizedBox(height: 10),
            _sectionTitle('Classes d\'âge'),
            const SizedBox(height: 4),
            _glossRow('J / JIN', 'Jeune — moins de 10 ans'),
            _glossRow('10', '10 à 20 ans'),
            _glossRow('20', '20 à 30 ans'),
            _glossRow('30', '30 à 40 ans'),
            _glossRow('40', '40 à 50 ans'),
            _glossRow('50', '50 à 60 ans'),
            _glossRow('60', '60 à 80 ans'),
            _glossRow('80', '80 à 100 ans'),
            _glossRow('100 / VIN', 'Plus de 100 ans'),
            const SizedBox(height: 10),
            _sectionTitle('Densité'),
            const SizedBox(height: 4),
            _glossRow('A', 'Éparse (< 25%)'),
            _glossRow('B', 'Clairsemée (25–40%)'),
            _glossRow('C', 'Semi-dense (40–60%)'),
            _glossRow('D', 'Dense (60–80%)'),
          ],
        ),
      ),
      actions: const [],
    ),
  );
}
