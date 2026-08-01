import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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
  static String get _productId => Platform.isIOS
      ? 'com.bastienbouchard.ecomap.pro'
      : 'orignalscan_premium_lifetime';

  StreamSubscription<List<PurchaseDetails>>? _iapSub;
  ProductDetails? _product;
  bool _loading = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _initIAP();
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
    if (_product == null) {
      setState(() => _erreur = 'Chargement en cours — réessaie dans quelques secondes');
      return;
    }
    setState(() { _loading = true; _erreur = null; });
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: _product!),
    );
  }

  Future<void> _restaurer() async {
    setState(() { _loading = true; _erreur = null; });
    await InAppPurchase.instance.restorePurchases();
  }

  String get _prix => _product != null ? _product!.price : '39,99 \$ CAD';

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6B35);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: orange.withOpacity(0.35), width: 1.2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1A0A00), Color(0xFF0D0D0D), Color(0xFF0D0D0D), Color(0xFF1A0A00)],
              stops: [0.0, 0.25, 0.75, 1.0],
            ),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height - 48,
          ),
          child: Stack(children: [
            Positioned(
              bottom: 0, left: 0, right: 0, height: 130,
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomCenter, radius: 1.2,
                    colors: [orange.withOpacity(0.22), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                      children: [
                        TextSpan(text: 'Orignal SCAN ', style: TextStyle(color: Colors.white)),
                        TextSpan(text: 'Pro', style: TextStyle(color: Color(0xFFFF6B35))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text('Accédez à l\'expérience complète, sans limites.',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: orange.withOpacity(0.3)),
                    ),
                    child: Column(children: [
                      const Text('Achat unique — pas d\'abonnement',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      const Text('39,99 \$ CAD',
                          style: TextStyle(color: Color(0xFFFF6B35), fontSize: 24,
                              fontWeight: FontWeight.w900)),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _section('ALGORITHMES', Icons.settings_rounded, const [
                    (Icons.local_fire_department, Color(0xFFFF6B35), 'Zones actives'),
                    (Icons.adjust_rounded, Color(0xFF42A5F5), 'Parcours optimisés'),
                    (Icons.radar_rounded, Color(0xFFEF5350), 'Postes d\'affût avancés'),
                    (Icons.view_in_ar_rounded, Color(0xFF42A5F5), 'Salines détaillées'),
                  ]),
                  const SizedBox(height: 10),
                  _section('INFORMATIONS & GROUPES', Icons.square_rounded, const [
                    (Icons.home_rounded, Color(0xFFFF6B35), 'Terres privées — cadastre complet'),
                    (Icons.forest_rounded, Color(0xFF4CAF50), 'Carte écoforestière MRNF'),
                    (Icons.people, Color(0xFFFF6B35), 'Groupe de chasseurs'),
                  ]),
                  const SizedBox(height: 10),
                  Text('Profitez de toutes les fonctionnalités Premium, pour toujours.',
                      style: TextStyle(color: Colors.white.withOpacity(0.5),
                          fontSize: 11, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center),
                  if (_erreur != null) ...[
                    const SizedBox(height: 6),
                    Text(_erreur!, style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB34000), Color(0xFFFF6B35), Color(0xFFFF8C42)],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: orange.withOpacity(0.5), blurRadius: 12)],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: _loading ? null : _acheter,
                        child: _loading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Passer à Orignal SCAN Pro',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('Pas maintenant',
                          style: TextStyle(color: Colors.white24, fontSize: 11)),
                    ),
                    const Text(' · ', style: TextStyle(color: Colors.white12, fontSize: 11)),
                    TextButton(
                      onPressed: _loading ? null : _restaurer,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('Restaurer',
                          style: TextStyle(color: Colors.white24, fontSize: 11)),
                    ),
                  ]),
                ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String label, IconData icon, List<(IconData, Color, String)> items) {
    const orange = Color(0xFFFF6B35);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: orange.withOpacity(0.5)),
        color: Colors.black26,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Divider(color: Color(0xFFFF6B35), thickness: 0.5)),
          const SizedBox(width: 8),
          Icon(icon, color: orange, size: 15),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 11,
              fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: Color(0xFFFF6B35), thickness: 0.5)),
        ]),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(item.$1, color: item.$2, size: 18),
            const SizedBox(width: 10),
            Text(item.$3, style: const TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w500)),
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
  static String get _productId => Platform.isIOS
      ? 'com.bastienbouchard.ecomap.pro'
      : 'orignalscan_premium_lifetime';

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
    _initIAP();
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

  Future<void> _acheter() async {
    if (_product == null) {
      setState(() => _erreur = 'Produit non chargé — réessaie dans quelques secondes');
      return;
    }
    setState(() { _loading = true; _erreur = null; });
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: _product!),
    );
  }

  Future<void> _restaurer() async {
    setState(() { _loading = true; _erreur = null; });
    await InAppPurchase.instance.restorePurchases();
  }

  String get _prixAffiche {
    if (_product != null) return _product!.price;
    return '39,99 \$ CAD';
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
                  child: const Text('Orignal SCAN Pro',
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
                onPressed: _loading ? null : _acheter,
                child: _loading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Obtenir Orignal SCAN Pro — $_prixAffiche',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),

            Center(
              child: TextButton(
                onPressed: _loading ? null : _restaurer,
                child: const Text('Restaurer mes achats',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ),

            const SizedBox(height: 4),
            Center(
              child: Text(
                Platform.isIOS
                    ? 'Paiement via App Store.\nAucun renouvellement — accès permanent.'
                    : 'Paiement via Google Play.\nAucun renouvellement — accès permanent.',
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
