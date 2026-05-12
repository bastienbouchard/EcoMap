import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});
  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  // ── Remplace ces URLs par tes liens Stripe Checkout ──
  static const _stripeUrlSaison = 'https://buy.stripe.com/PLACEHOLDER_SAISON';
  static const _stripeUrlVie    = 'https://buy.stripe.com/PLACEHOLDER_VIE';

  int _selected = 0; // 0 = saison, 1 = à vie

  static const _features = [
    (Icons.local_fire_department, '🔥 Points chauds orignal',
        'Détection automatique des meilleurs habitats dans la zone visible.'),
    (Icons.route, '🗺 Parcours optimisé IA',
        'Itinéraire calculé selon le vent, le terrain et les hotspots.'),
    (Icons.cabin, '🏕 Postes d\'affût',
        'Corridors naturels où l\'orignal est forcé de passer — rayon 3 km.'),
    (Icons.people, '👥 Groupe de chasseurs',
        'Positions en temps réel, clavardage et partage d\'observations.'),
    (Icons.share, '📡 Partage de traces et observations',
        'Envoie tes tracés GPS, photos et observations à ton groupe.'),
    (Icons.map, '🗾 Carte écoforestière MRNF',
        'Analyse peuplement, âge, drainage et perturbation par secteur.'),
    (Icons.fence, '📐 Terres privées et publiques',
        'Délimitations cadastrales et terres de la Couronne superposées.'),
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
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── En-tête ──
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.5)),
              ),
              child: const Text('PREMIUM',
                  style: TextStyle(
                    color: Color(0xFFFF6B35),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  )),
            ),
            const SizedBox(height: 16),
            const Text('OrignalScan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                )),
            const SizedBox(height: 8),
            const Text(
              'L\'assistant de chasse à l\'orignal\nle plus avancé au Québec.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),

            // ── Fonctionnalités ──
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.2)),
              ),
              child: Column(
                children: _features.asMap().entries.map((e) {
                  final i = e.key;
                  final f = e.value;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B35).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(f.$1, color: const Color(0xFFFF6B35), size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.$2,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(f.$3,
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 11, height: 1.4)),
                                ],
                              ),
                            ),
                            const Icon(Icons.check_circle,
                                color: Color(0xFF4CAF50), size: 18),
                          ],
                        ),
                      ),
                      if (i < _features.length - 1)
                        const Divider(height: 1, color: Colors.white10),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 32),

            // ── Sélection de plan ──
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Choisir un plan',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
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
            const SizedBox(height: 28),

            // ── Bouton d'achat ──
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
                  _selected == 0 ? 'Obtenir — 19,99 \$/saison' : 'Obtenir — 49,99 \$ à vie',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Paiement sécurisé par Stripe.\nAucun abonnement automatique.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
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
        child: Row(
          children: [
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          )),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
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
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            Text(price,
                style: TextStyle(
                  color: selected ? const Color(0xFFFF6B35) : Colors.white54,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                )),
          ],
        ),
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
