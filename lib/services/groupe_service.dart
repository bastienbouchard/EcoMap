import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class GroupeService {
  static final _db = FirebaseFirestore.instance;
  static const _collection = 'groupe_positions';

  // Publie la position de ce chasseur
  static Future<void> publierPosition({
    required String groupeId,
    required String nom,
    required LatLng position,
  }) async {
    await _db.collection(_collection).doc('${groupeId}_$nom').set({
      'groupeId': groupeId,
      'nom': nom,
      'lat': position.latitude,
      'lon': position.longitude,
      'ts': FieldValue.serverTimestamp(),
    });
  }

  // Écoute les positions des autres membres du groupe
  static Stream<List<MembreGroupe>> ecouterGroupe(String groupeId, String monNom) {
    return _db
        .collection(_collection)
        .where('groupeId', isEqualTo: groupeId)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d['nom'] != monNom) // exclure sa propre position
            .map((d) => MembreGroupe(
                  nom: d['nom'] as String,
                  position: LatLng(
                    (d['lat'] as num).toDouble(),
                    (d['lon'] as num).toDouble(),
                  ),
                  ts: (d['ts'] as Timestamp?)?.toDate(),
                ))
            .toList());
  }

  // Écoute les observations partagées par les autres membres
  static Stream<List<Map<String, dynamic>>> ecouterObservations(
      String groupeId, String monNom) {
    return _db
        .collection('groupes')
        .doc(groupeId)
        .collection('observations')
        .orderBy('ts', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d['nom'] != monNom)
            .map((d) => {
                  'nom': d['nom'] as String,
                  'note': d['note'] as String,
                  'lat': (d['lat'] as num).toDouble(),
                  'lon': (d['lon'] as num).toDouble(),
                })
            .toList());
  }

  // Écoute les tracés partagés par les autres membres
  static Stream<List<Map<String, dynamic>>> ecouterTraces(
      String groupeId, String monNom) {
    return _db
        .collection('groupes')
        .doc(groupeId)
        .collection('traces')
        .orderBy('ts', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d['nom'] != monNom)
            .map((d) => {
                  'nom': d['nom'] as String,
                  'date': d['date'] as String,
                  'points': (d['points'] as List)
                      .map((p) => {
                            'lat': (p['lat'] as num).toDouble(),
                            'lon': (p['lon'] as num).toDouble(),
                          })
                      .toList(),
                })
            .toList());
  }

  // Publie un point épinglé dans le groupe
  static Future<void> publierEpingle({
    required String groupeId,
    required String nom,
    required String type,
    required double lat,
    required double lon,
  }) async {
    final id = '${groupeId}_${nom}_${lat.toStringAsFixed(5)}_${lon.toStringAsFixed(5)}';
    await _db.collection('groupes').doc(groupeId).collection('epingles').doc(id).set({
      'nom': nom,
      'type': type,
      'lat': lat,
      'lon': lon,
      'ts': FieldValue.serverTimestamp(),
    });
  }

  // Supprime un point épinglé du groupe
  static Future<void> supprimerEpingle({
    required String groupeId,
    required String nom,
    required double lat,
    required double lon,
  }) async {
    final id = '${groupeId}_${nom}_${lat.toStringAsFixed(5)}_${lon.toStringAsFixed(5)}';
    await _db.collection('groupes').doc(groupeId).collection('epingles').doc(id).delete();
  }

  // Écoute les épingles partagées par les autres membres
  static Stream<List<Map<String, dynamic>>> ecouterEpingles(
      String groupeId, String monNom) {
    return _db
        .collection('groupes')
        .doc(groupeId)
        .collection('epingles')
        .snapshots()
        .map((snap) => snap.docs
            .where((d) => d['nom'] != monNom)
            .map((d) => {
                  'nom': d['nom'] as String,
                  'type': d['type'] as String,
                  'lat': (d['lat'] as num).toDouble(),
                  'lon': (d['lon'] as num).toDouble(),
                })
            .toList());
  }

  // Supprime la position quand on quitte
  static Future<void> quitter(String groupeId, String nom) async {
    await _db.collection(_collection).doc('${groupeId}_$nom').delete();
  }
}

class MembreGroupe {
  final String nom;
  final LatLng position;
  final DateTime? ts;

  MembreGroupe({required this.nom, required this.position, this.ts});
}
