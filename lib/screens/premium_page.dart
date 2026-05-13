import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});
  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  // ── Remplace par tes vrais liens Stripe Checkout ──
  static const _stripeUrlSaison = 'https://buy.stripe.com/PLACEHOLDER_SAISON';
  static const _stripeUrlVie    = 'https://buy.stripe.com/PLACEHOLDER_VIE';

  int _selected = 0; // 0 = saison, 1 = à vie

  static const _freeFeatures = [
    (Icons.gps_fixed_rounded,       'GPS & localisation'),
    (Icons.map_rounded,             'Carte OpenStreetMap'),
    (Icons.satellite_alt_rounded,   'Carte satellite'),
    (Icons.push_pin_rounded,        'Observations terrain'),
    (Icons.route_rounded,           'Tracé GPS'),
  ];

  static const _proFeatures = [
    (Icons.local_fire_department,   '🔥 Points chauds orignal',
        'Détection des meilleurs habitats dans la zone visible.'),
    (Icons.route,                   '🗺 Parcours optimisé IA',
        'Itinéraire calculé selon le vent, le terrain et les hotspots.'),
    (Icons.cabin,                   '🏕 Postes d\'affût',
        'Corridors naturels où l\'orignal est forcé de passer — rayon 3 km.'),
    (Icons.people,                  '👥 Groupe de chasseurs',
        'Positions en temps réel, clavardage et partage d\'observations.'),
    (Icons.map,                     '🗾 Carte écoforestière MRNF',
        'Peuplement, âge, drainage et perturbation par secteur.'),
    (Icons.fence,                   '📐 Terres privées cadastrales',
        'Délimitations de lots — tap pour télécharger la carte éco.'),
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

            // ── Choisir un plan ──
            const Text('Choisir un plan',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _planCard(
              selected: _selected == 0,
              title: 'Par saison',
              price: '19,99 \$',
              subtitle: 'Accès jusqu\'au 31 décembre',
              badge: null,
              onTap: () => setState(() => _selected = 0),
            ),
            const SizedBox(height: 10),
            _planCard(
              selected: _selected == 1,
              title: 'À vie',
              price: '49,99 \$',
              subtitle: 'Un seul paiement — toutes les saisons',
              badge: 'MEILLEURE VALEUR',
              onTap: () => setState(() => _selected = 1),
            ),
            const SizedBox(height: 24),

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
                child: Text(
                  _selected == 0
                      ? 'Obtenir Pro — 19,99 \$/saison'
                      : 'Obtenir Pro — 49,99 \$ à vie',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'Paiement sécurisé par Stripe.\nAucun renouvellement automatique.',
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

  Widget _planCard({
    required bool selected,
    required String title,
    required String price,
    required String subtitle,
    required String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFF6B35).withOpacity(0.12)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFFF6B35) : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22, height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? const Color(0xFFFF6B35) : Colors.white30,
                width: 2,
              ),
              color: selected ? const Color(0xFFFF6B35) : Colors.transparent,
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white, size: 13)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF4CAF50).withOpacity(0.5)),
                    ),
                    child: Text(badge,
                        style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          )),
          Text(price,
              style: TextStyle(
                color: selected ? const Color(0xFFFF6B35) : Colors.white54,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )),
        ]),
      ),
    );
  }

  Future<void> _acheter() async {
    final url = _selected == 0 ? _stripeUrlSaison : _stripeUrlVie;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
