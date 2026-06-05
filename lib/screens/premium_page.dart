import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/premium_service.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});
  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  static const _productId = 'orignalscan_pro_lifetime';
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
    if (_product == null) return;
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
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

            // Prix
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
                    Text('Accès à vie', style: TextStyle(color: Colors.white,
                        fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Un seul paiement — toutes les saisons futures',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                )),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
<<<<<<< HEAD
                    const Text('39,99 \$',
                        style: TextStyle(color: Color(0xFFFF6B35),
                            fontSize: 26, fontWeight: FontWeight.bold)),
=======
                    Text(_prixAffiche, style: const TextStyle(color: Color(0xFFFF6B35),
                        fontSize: 26, fontWeight: FontWeight.bold)),
>>>>>>> 83b586b (iOS IAP via StoreKit, Android via Stripe)
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

            // Bouton principal
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
<<<<<<< HEAD
                onPressed: _iapLoading ? null : _acheter,
                child: _iapLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Obtenir OrignalScan Pro — 39,99 \$',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 12),
=======
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
>>>>>>> 83b586b (iOS IAP via StoreKit, Android via Stripe)
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
<<<<<<< HEAD

  Future<void> _acheter() async {
    if (Platform.isIOS) {
      await _acheterIAP();
    } else {
      await _acheterStripe();
    }
  }

  Future<void> _acheterStripe() async {
    final uid = AuthService.uid;
    if (uid == null) return;
    final uri = Uri.parse('$_stripeUrl?client_reference_id=$uid');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _acheterIAP() async {
    setState(() => _iapLoading = true);
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        if (mounted) _snackErreur('App Store non disponible');
        return;
      }
      final response = await InAppPurchase.instance
          .queryProductDetails({_iapId});
      if (response.productDetails.isEmpty) {
        if (mounted) _snackErreur('Produit introuvable');
        return;
      }
      final product = response.productDetails.first;
      final purchaseParam = PurchaseParam(productDetails: product);
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: purchaseParam);

      // Écouter le résultat
      InAppPurchase.instance.purchaseStream.listen((purchases) async {
        for (final purchase in purchases) {
          if (purchase.productID == _iapId &&
              purchase.status == PurchaseStatus.purchased) {
            await InAppPurchase.instance.completePurchase(purchase);
            await PremiumService.activerPremium();
            if (mounted) Navigator.pop(context);
          } else if (purchase.status == PurchaseStatus.error) {
            if (mounted) _snackErreur('Erreur lors de l\'achat');
          }
        }
      });
    } catch (e) {
      if (mounted) _snackErreur('Erreur : $e');
    } finally {
      if (mounted) setState(() => _iapLoading = false);
    }
  }

  void _snackErreur(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }
=======
>>>>>>> 83b586b (iOS IAP via StoreKit, Android via Stripe)
}
