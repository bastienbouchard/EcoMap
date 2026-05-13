import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});
  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  // ── Remplace par ton vrai lien Stripe Checkout ──
  static const _stripeUrl = 'https://buy.stripe.com/PLACEHOLDER_VIE';

  static const _freeFeatures = [
    (Icons.gps_fixed_rounded,       'GPS & localisation'),
    (Icons.map_rounded,             'Carte OpenStreetMap'),
    (Icons.satellite_alt_rounded,   'Carte satellite'),
    (Icons.push_pin_rounded,        'Observations terrain'),
    (Icons.route_rounded,           'Tracé GPS'),
  ];

  static const _proFeatures = [
    (Icons.local_fire_department,   '🔥 Points chauds orignal',
        'Algorithme IA qui détecte les meilleurs habitats dans la zone visible.'),
    (Icons.route,                   '🗺 Parcours optimisé — algorithme IA',
        'Itinéraire calculé selon le vent, le terrain et les hotspots.'),
    (Icons.cabin,                   '🏕 Postes d\'affût — algorithme IA',
        'Détecte les corridors naturels où l\'orignal est forcé de passer — rayon 3 km.'),
    (Icons.water_drop_rounded,      '🧂 Salines à orignal — algorithme IA',
        'Identifie les zones humides idéales pour installer une saline et attirer l\'orignal.'),
    (Icons.map,                     '🗾 Carte écoforestière MRNF',
        'Peuplement, âge, drainage et perturbation par secteur.'),
    (Icons.fence,                   '📐 Terres privées — cadastre des lots',
        'Limites de lots cadastraux — tap pour télécharger la carte éco du lot.'),
    (Icons.people,                  '👥 Groupe de chasseurs',
        'Positions en temps réel, clavardage et partage d\'observations.'),
    (Icons.share,                   '📡 Partage traces et observations',
        'Envoie tes tracés GPS et observations à ton groupe.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFFF6B35)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête ──
            Center(
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.5)),
                  ),
                  child: const Text('OrignalScan PRO',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      )),
                ),
                const SizedBox(height: 12),
                const Text('L\'assistant de chasse à l\'orignal\nle plus avancé au Québec.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
              ]),
            ),
            const SizedBox(height: 28),

            // ── Gratuit ──
            _sectionHeader('GRATUIT', Colors.white38),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: _freeFeatures.asMap().entries.map((e) {
                  final f = e.value;
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: Row(children: [
                        Icon(f.$1, color: Colors.white54, size: 18),
                        const SizedBox(width: 12),
                        Expanded(child: Text(f.$2,
                            style: const TextStyle(color: Colors.white70, fontSize: 13))),
                        const Icon(Icons.check_circle_outline,
                            color: Colors.white38, size: 16),
                      ]),
                    ),
                    if (e.key < _freeFeatures.length - 1)
                      const Divider(height: 1, color: Colors.white10),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

            // ── Pro ──
            _sectionHeader('PRO', const Color(0xFFFF6B35)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.35)),
              ),
              child: Column(
                children: _proFeatures.asMap().entries.map((e) {
                  final f = e.value;
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(f.$1, color: const Color(0xFFFF6B35), size: 17),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.$2,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(f.$3,
                                  style: const TextStyle(color: Colors.white38,
                                      fontSize: 11, height: 1.4)),
                            ],
                          )),
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Icon(Icons.check_circle,
                                color: Color(0xFF4CAF50), size: 16),
                          ),
                        ],
                      ),
                    ),
                    if (e.key < _proFeatures.length - 1)
                      const Divider(height: 1, color: Colors.white10),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 28),

            // ── Prix ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withOpacity(0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.5), width: 1.5),
              ),
              child: Row(children: [
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Accès à vie',
                        style: TextStyle(color: Colors.white,
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Un seul paiement — toutes les saisons futures',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                )),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('49,99 \$',
                        style: TextStyle(color: Color(0xFFFF6B35),
                            fontSize: 26, fontWeight: FontWeight.bold)),
                    Text('CAD', style: TextStyle(
                        color: const Color(0xFFFF6B35).withOpacity(0.7), fontSize: 11)),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Bouton ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                onPressed: _acheter,
                child: const Text('Obtenir OrignalScan Pro — 49,99 \$',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Paiement sécurisé par Stripe.\nAucun renouvellement — accès permanent.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, Color color) {
    return Row(children: [
      Text(label,
          style: TextStyle(
              color: color, fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: color.withOpacity(0.3), height: 1)),
    ]);
  }

  Future<void> _acheter() async {
    final uri = Uri.parse(_stripeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
