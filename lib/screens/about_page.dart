import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'onboarding_page.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  Future<void> _supprimerCompte() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Supprimer le compte',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
            'Cette action est irréversible. Ton compte et toutes tes données seront supprimés définitivement.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await AuthService.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur : $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _resetOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Onboarding réinitialisé — redémarre l\'app')),
    );
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingPage(onDone: () => Navigator.pop(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('À propos', style: TextStyle(color: Colors.white)),
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
          Center(
            child: Column(children: [
              const SizedBox(height: 8),
              GestureDetector(
                onLongPress: _resetOnboarding,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  child: Image.asset('assets/logo.png', height: 72),
                ),
              ),
              const SizedBox(height: 12),
              const Text('OrignalScan',
                  style: TextStyle(color: Colors.white, fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const Text('Habitat orignal — Québec',
                  style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => launchUrl(
                  Uri.parse('https://www.orignalscan.com'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.language, color: Color(0xFFFF6B35), size: 14),
                    SizedBox(width: 6),
                    Text('orignalscan.com',
                        style: TextStyle(color: Color(0xFFFF6B35), fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OnboardingPage(
                      onDone: () => Navigator.pop(context),
                    ),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline,
                    color: Color(0xFFFF6B35), size: 18),
                label: const Text('Menu info',
                    style: TextStyle(color: Color(0xFFFF6B35), fontSize: 13)),
              ),
              const SizedBox(height: 8),
            ]),
          ),
          _card(children: [
            _title('Méthodologie de l\'habitat'),
            const SizedBox(height: 8),
            const Text(
              'L\'algorithme est basé sur les principes de l\'écologie de l\'orignal documentés par le MRNF et les universités québécoises (UQAR, UQAM) :\n\n'
              '• Alimentation — L\'orignal est un herbivore brouteur. Il préfère les jeunes peuplements feuillus (peuplier faux-tremble, aulne rugueux, saule, bouleau à papier) qui poussent dans les coupes et brûlis récents (5–25 ans).\n\n'
              '• Abri — Les résineux denses (épinette, sapin) servent de protection thermique en automne et de couvert de sécurité.\n\n'
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
            _title('Compte'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _supprimerCompte,
              child: Row(children: [
                const Icon(Icons.delete_forever, color: Colors.redAccent, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Supprimer mon compte',
                        style: TextStyle(color: Colors.redAccent, fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    Text('Supprime définitivement ton compte et toutes tes données',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          _card(children: [
            _title('Fonctions principales'),
            const SizedBox(height: 8),
            _item('🔥 Points chauds', 'Détecte les meilleurs habitats orignal dans la zone visible.'),
            _item('🗺 Parcours optimisé', 'Itinéraire calculé selon le vent, le terrain et les hotspots.'),
            _item('🏕 Postes d\'affût', 'Corridors naturels où l\'orignal est forcé de passer — rayon 3 km.'),
            _item('🧂 Salines', 'Identifie les zones humides idéales pour installer une saline.'),
            _item('🗾 Carte écoforestière', 'Peuplement, âge, drainage et perturbation par secteur.'),
            _item('📐 Terres privées', 'Limites de lots cadastraux — tap pour télécharger la carte éco du lot.'),
            _item('👥 Groupe de chasseurs', 'Positions en temps réel, clavardage et partage d\'observations.'),
            _item('📡 Partage traces', 'Envoie tes tracés GPS et observations à ton groupe.'),
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
}
