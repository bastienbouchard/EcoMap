import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/premium_service.dart';

// ─── Popup compact (utilisé depuis _requirePremium) ──────────────────────────

class PremiumPopup extends StatefulWidget {
  const PremiumPopup({super.key});
  @override
  State<PremiumPopup> createState() => _PremiumPopupState();
}

class _PremiumPopupState extends State<PremiumPopup> {
  static const _productId = 'com.bastienbouchard.ecomap.pro';
  static const _stripeUrl = 'https://buy.stripe.com/bJe7sL81HcyfgQi1oX83C01';

  StreamSubscription<List<PurchaseDetails>>? _iapSub;
  ProductDetails? _product;
  bool _loading = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) _initIAP();
  }

  @override
  void dispose() {
    _iapSub?.cancel();
    super.dispose();
  }

  Future<void> _initIAP() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available || !mounted) return;
    _iapSub = InAppPurchase.instance.purchaseStream.listen(_onPurchaseUpdate);
    final resp = await InAppPurchase.instance.queryProductDetails({_productId});
    if (!mounted) return;
    if (resp.productDetails.isNotEmpty) {
      setState(() => _product = resp.productDetails.first);
    } else {
      setState(() => _erreur = 'Produit introuvable');
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != _productId) continue;
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        await _activerPremium();
        await InAppPurchase.instance.completePurchase(p);
      } else if (p.status == PurchaseStatus.error) {
        if (mounted) setState(() { _loading = false; _erreur = p.error?.message; });
      } else if (p.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _loading = true);
      }
    }
  }

  Future<void> _activerPremium() async {
    final uid = AuthService.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'premium': true});
      await PremiumService.load();
    }
    if (mounted) {
      setState(() => _loading = false);
      Navigator.pop(context);
    }
  }

  Future<void> _acheter() async {
    if (Platform.isIOS) {
      if (_product == null) {
        setState(() => _erreur = 'Chargement en cours — réessaie dans quelques secondes');
        return;
      }
      setState(() { _loading = true; _erreur = null; });
      await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: _product!),
      );
    } else {
      final uid = AuthService.uid;
      if (uid == null) return;
      final uri = Uri.parse('$_stripeUrl?client_reference_id=$uid');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  String get _prix => Platform.isIOS && _product != null ? _product!.price : '39,99 \$';

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4CAF50);
    const blue = Color(0xFF42A5F5);
    const orange = Color(0xFFFF6B35);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 24)],
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('OrigianlScan Pro',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                const Text('Accédez à des fonctionnalités avancées.',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ])),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD45A00), Color(0xFFFF8C42)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: orange.withOpacity(0.4), blurRadius: 8)],
                ),
                child: Column(children: [
                  const Text('Passez à Pro pour', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
                  Text(_prix, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),

            // ── Section ALGORITHMES ──
            _section(
              color: green,
              icon: Icons.psychology_rounded,
              label: 'ALGORITHMES',
              items: const [
                (Icons.local_fire_department, orange, 'Zones actives originales'),
                (Icons.route_rounded, green, 'Parcours optimisé'),
                (Icons.cabin, green, 'Postes d\'affût'),
                (Icons.water_drop, orange, 'Salines originales'),
              ],
            ),
            const SizedBox(height: 10),

            // ── Section INFORMATIONS & GROUPES ──
            _section(
              color: blue,
              icon: Icons.info_outline_rounded,
              label: 'INFORMATIONS & GROUPES',
              items: const [
                (Icons.fence_rounded, orange, 'Terres privées — cadastre des lots'),
                (Icons.forest_rounded, orange, 'Carte écoforestière MRNF'),
                (Icons.people, orange, 'Groupe de chasseurs'),
              ],
            ),

            if (_erreur != null) ...[
              const SizedBox(height: 8),
              Text(_erreur!, style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 14),

            // ── Boutons ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                onPressed: _loading ? null : _acheter,
                child: _loading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Passer à OrigianlScan Pro',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Pas maintenant',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required Color color,
    required IconData icon,
    required String label,
    required List<(IconData, Color, String)> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(item.$1, color: item.$2, size: 17),
            const SizedBox(width: 10),
            Text(item.$3, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
        )),
      ]),
    );
  }
}

// ─── Page complète (garde pour compatibilité) ─────────────────────────────────

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});
  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  static const _productId = 'com.bastienbouchard.ecomap.pro';
  static const _stripeUrl = 'https://buy.stripe.com/bJe7sL81HcyfgQi1oX83C01';

  StreamSubscription<List<PurchaseDetails>>? _iapSub;
  ProductDetails? _product;
  bool _loading = false;
  String? _erreur;

  static const _freeFeatures = [
    (Icons.gps_fixed_rounded,       'GPS & localisation'),
    (Icons.map_rounded,             'Carte OpenStreetMap'),
    (Icons.satellite_alt_rounded,   'Carte satellite'),
    (Icons.push_pin_rounded,        'Observations terrain'),
    (Icons.route_rounded,           'Tracé GPS'),
  ];

  static const _proFeatures = [
    (Icons.local_fire_department,   '🔥 Zones actives orignal',
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
  void initState() {
    super.initState();
    if (Platform.isIOS) _initIAP();
  }

  @override
  void dispose() {
    _iapSub?.cancel();
    super.dispose();
  }

  Future<void> _initIAP() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      if (mounted) setState(() => _erreur = 'App Store non disponible');
      return;
    }
    if (!mounted) return;

    _iapSub = InAppPurchase.instance.purchaseStream.listen(_onPurchaseUpdate);

    final resp = await InAppPurchase.instance.queryProductDetails({_productId});
    if (!mounted) return;
    if (resp.productDetails.isNotEmpty) {
      setState(() => _product = resp.productDetails.first);
    } else {
      final detail = resp.error?.message ?? resp.notFoundIDs.join(', ');
      setState(() => _erreur = 'Produit introuvable ($detail)');
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID != _productId) continue;
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        await _activerPremium();
        await InAppPurchase.instance.completePurchase(p);
      } else if (p.status == PurchaseStatus.error) {
        if (mounted) setState(() { _loading = false; _erreur = p.error?.message; });
      } else if (p.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _loading = true);
      }
    }
  }

  Future<void> _activerPremium() async {
    final uid = AuthService.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'premium': true});
      await PremiumService.load();
    }
    if (mounted) {
      setState(() => _loading = false);
      Navigator.pop(context);
    }
  }

  Future<void> _acheterIOS() async {
    if (_product == null) {
      setState(() => _erreur = 'Produit non chargé — réessaie dans quelques secondes');
      return;
    }
    setState(() { _loading = true; _erreur = null; });
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: _product!),
    );
  }

  Future<void> _restaurerIOS() async {
    setState(() { _loading = true; _erreur = null; });
    await InAppPurchase.instance.restorePurchases();
  }

  Future<void> _acheterAndroid() async {
    final uid = AuthService.uid;
    if (uid == null) return;
    final uri = Uri.parse('$_stripeUrl?client_reference_id=$uid');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String get _prixAffiche {
    if (Platform.isIOS && _product != null) return _product!.price;
    return '39,99 \$';
  }

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
        padding: EdgeInsets.fromLTRB(20, 0, 20, 40 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                      style: TextStyle(color: Color(0xFFFF6B35), fontSize: 12,
                          fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
                const SizedBox(height: 12),
                const Text('L\'assistant de chasse à l\'orignal\nle plus avancé au Québec.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
              ]),
            ),
            const SizedBox(height: 28),

            _sectionHeader('GRATUIT', Colors.white38),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
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
                        const Icon(Icons.check_circle_outline, color: Colors.white38, size: 16),
                      ]),
                    ),
                    if (e.key < _freeFeatures.length - 1)
                      const Divider(height: 1, color: Colors.white10),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),

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
                              Text(f.$2, style: const TextStyle(color: Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(f.$3, style: const TextStyle(color: Colors.white38,
                                  fontSize: 11, height: 1.4)),
                            ],
                          )),
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
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
                    Text('Paiement unique', style: TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Un seul paiement — toutes les saisons futures',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                )),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_prixAffiche, style: const TextStyle(color: Color(0xFFFF6B35),
                        fontSize: 26, fontWeight: FontWeight.bold)),
                    Text('CAD', style: TextStyle(
                        color: const Color(0xFFFF6B35).withOpacity(0.7), fontSize: 11)),
                  ],
                ),
              ]),
            ),
            const SizedBox(height: 16),

            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_erreur!, style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    textAlign: TextAlign.center),
              ),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                onPressed: _loading ? null : (Platform.isIOS ? _acheterIOS : _acheterAndroid),
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Obtenir OrignalScan Pro — $_prixAffiche',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),

            if (Platform.isIOS)
              Center(
                child: TextButton(
                  onPressed: _loading ? null : _restaurerIOS,
                  child: const Text('Restaurer mes achats',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ),
              ),

            const SizedBox(height: 4),
            Center(
              child: Text(
                Platform.isIOS
                    ? 'Paiement via App Store.\nAucun renouvellement — accès permanent.'
                    : 'Paiement sécurisé par Stripe.\nAucun renouvellement — accès permanent.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String label, Color color) {
    return Row(children: [
      Text(label, style: TextStyle(color: color, fontSize: 11,
          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: color.withOpacity(0.3), height: 1)),
    ]);
  }
}
