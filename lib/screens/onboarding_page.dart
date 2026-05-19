import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import 'map_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('has_seen_onboarding') ?? false);
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
  }

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _current = 0;
  static const _total = 7;
  static const _stripeUrl = 'https://buy.stripe.com/bJeaEXeq59m3bvY9Vt83C00';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_current < _total - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _skipToEnd() {
    _controller.animateToPage(
      _total - 1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    await OnboardingPage.markDone();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MapPage()),
    );
  }

  Future<void> _goPro() async {
    final uid = AuthService.uid;
    if (uid != null) {
      final uri = Uri.parse('$_stripeUrl?client_reference_id=$uid');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    await OnboardingPage.markDone();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MapPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _current == _total - 1;
    final isPremiumSlide = _current >= 3 && !isLast;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: Column(
          children: [
            // Top row: logo left, skip right
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                          Colors.white38, BlendMode.srcIn),
                      child: Image.asset('assets/logo.png', height: 22),
                    ),
                  ),
                  const Spacer(),
                  if (!isLast)
                    TextButton(
                      onPressed: _skipToEnd,
                      child: const Text('Passer',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 13)),
                    )
                  else
                    const SizedBox(height: 40),
                ],
              ),
            ),

            // Page content
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _current = i),
                children: [
                  _buildWelcomeSlide(),
                  _buildFeatureSlide(
                    icon: Icons.map_rounded,
                    color: const Color(0xFF4FC3F7),
                    tag: 'GRATUIT',
                    isPro: false,
                    title: 'Carte & GPS',
                    description:
                        'Localise-toi en temps réel sur la carte '
                        'OpenStreetMap ou passe en vue satellite d\'un seul '
                        'tap. Fonctionne même en forêt dense.',
                    secondIcon: Icons.satellite_alt_rounded,
                  ),
                  _buildFeatureSlide(
                    icon: Icons.push_pin_rounded,
                    color: const Color(0xFF81C784),
                    tag: 'GRATUIT',
                    isPro: false,
                    title: 'Observations & Tracés GPS',
                    description:
                        'Note tes observations terrain avec photos et '
                        'enregistre tes parcours GPS pour retrouver tes '
                        'meilleurs spots saison après saison.',
                    secondIcon: Icons.route_rounded,
                  ),
                  _buildFeatureSlide(
                    icon: Icons.local_fire_department,
                    color: const Color(0xFFFF6B35),
                    tag: 'PRO',
                    isPro: true,
                    title: 'Points chauds & Parcours IA',
                    description:
                        'Notre algorithme analyse les peuplements '
                        'forestiers MRNF et calcule les zones de présence '
                        'optimale. L\'itinéraire s\'adapte au vent pour une '
                        'approche parfaite.',
                    secondIcon: Icons.route,
                  ),
                  _buildFeatureSlide(
                    icon: Icons.cabin,
                    color: const Color(0xFFFF6B35),
                    tag: 'PRO',
                    isPro: true,
                    title: 'Postes, Salines & Cadastre',
                    description:
                        'Détecte les corridors naturels pour tes postes '
                        'd\'affût, identifie les zones humides idéales pour '
                        'une saline et consulte les limites cadastrales des '
                        'terres privées.',
                    secondIcon: Icons.water_drop_rounded,
                  ),
                  _buildFeatureSlide(
                    icon: Icons.people,
                    color: const Color(0xFFFF6B35),
                    tag: 'PRO',
                    isPro: true,
                    title: 'Groupe de chasseurs',
                    description:
                        'Vois les positions de tes partenaires en temps '
                        'réel sur la carte. Partage tes tracés, observations '
                        'et coordonne la chasse via la messagerie intégrée.',
                    secondIcon: Icons.share,
                  ),
                  _buildCtaSlide(),
                ],
              ),
            ),

            // Bottom: dots + button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_total, _dot),
                  ),
                  const SizedBox(height: 18),
                  if (!isLast)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPremiumSlide
                              ? const Color(0xFFFF6B35)
                              : const Color(0xFF2D5016),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _next,
                        child: const Text('Continuer',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ),
                    )
                  else ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B35),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 6,
                        ),
                        onPressed: _goPro,
                        child: const Text('Passer en Pro — 49,99 \$',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _finish,
                      child: const Text('Continuer en version gratuite',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 13)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(int index) {
    final active = index == _current;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFF6B35) : Colors.white24,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildWelcomeSlide() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                    Colors.white, BlendMode.srcIn),
                child: Image.asset('assets/logo.png'),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text('OrignalScan',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5)),
          const SizedBox(height: 12),
          const Text(
            'L\'assistant de chasse à l\'orignal\nle plus avancé au Québec.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white60, fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 32),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.3)),
            ),
            child: const Text(
              'Découvre tout ce que l\'app peut faire →',
              style:
                  TextStyle(color: Color(0xFFFF6B35), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureSlide({
    required IconData icon,
    required Color color,
    required String tag,
    required bool isPro,
    required String title,
    required String description,
    IconData? secondIcon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (isPro)
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withOpacity(0.06),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.25),
                        blurRadius: 35,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPro
                      ? color.withOpacity(0.14)
                      : Colors.white.withOpacity(0.07),
                  border: Border.all(
                    color:
                        isPro ? color.withOpacity(0.4) : Colors.white12,
                    width: 1.5,
                  ),
                ),
                child: secondIcon != null
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: color, size: 30),
                          const SizedBox(width: 5),
                          Icon(secondIcon,
                              color: color.withOpacity(0.65), size: 22),
                        ],
                      )
                    : Icon(icon, color: color, size: 42),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isPro
                  ? const Color(0xFFFF6B35).withOpacity(0.15)
                  : Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isPro
                    ? const Color(0xFFFF6B35).withOpacity(0.5)
                    : Colors.white24,
              ),
            ),
            child: Text(tag,
                style: TextStyle(
                    color: isPro
                        ? const Color(0xFFFF6B35)
                        : Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.2)),
          const SizedBox(height: 14),
          Text(description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                  height: 1.6)),
        ],
      ),
    );
  }

  Widget _buildCtaSlide() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.5)),
            ),
            child: const Text('OrignalScan PRO',
                style: TextStyle(
                    color: Color(0xFFFF6B35),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
          ),
          const SizedBox(height: 18),
          const Text('Prêt à chasser\nplus intelligemment?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  height: 1.2)),
          const SizedBox(height: 10),
          const Text(
            'Débloque les 8 fonctions avancées et repère\nles orignaux avant tout le monde.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white60, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 22),
          _miniFeature(Icons.local_fire_department,
              'Points chauds & Parcours IA'),
          _miniFeature(Icons.cabin, 'Postes d\'affût IA — rayon 3 km'),
          _miniFeature(
              Icons.water_drop_rounded, 'Salines à orignal IA'),
          _miniFeature(Icons.map, 'Carte écoforestière MRNF'),
          _miniFeature(Icons.fence, 'Cadastre des terres privées'),
          _miniFeature(Icons.people, 'Groupe de chasseurs temps réel'),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.5),
                  width: 1.5),
            ),
            child: Row(children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Accès à vie',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 2),
                    Text('Un seul paiement — toutes les saisons',
                        style: TextStyle(
                            color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('49,99 \$',
                      style: TextStyle(
                          color: Color(0xFFFF6B35),
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  Text('CAD',
                      style: TextStyle(
                          color: const Color(0xFFFF6B35).withOpacity(0.7),
                          fontSize: 10)),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 6),
          const Text(
            'Paiement sécurisé par Stripe.',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _miniFeature(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              Icon(icon, color: const Color(0xFFFF6B35), size: 15),
        ),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 13)),
        const Spacer(),
        const Icon(Icons.check_circle,
            color: Color(0xFF4CAF50), size: 16),
      ]),
    );
  }
}
