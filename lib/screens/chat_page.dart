import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../services/photo_picker.dart';

class ChatPage extends StatefulWidget {
  final String groupeId;
  final String monNom;

  const ChatPage({super.key, required this.groupeId, required this.monNom});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _db = FirebaseFirestore.instance;
  bool _envoyantPhoto = false;

  Stream<QuerySnapshot> get _messages => _db
      .collection('groupes')
      .doc(widget.groupeId)
      .collection('messages')
      .orderBy('ts', descending: false)
      .limitToLast(100)
      .snapshots();

  Future<void> _envoyer() async {
    final texte = _ctrl.text.trim();
    if (texte.isEmpty) return;
    _ctrl.clear();
    try {
      await _db
          .collection('groupes')
          .doc(widget.groupeId)
          .collection('messages')
          .add({
        'nom': widget.monNom,
        'texte': texte,
        'ts': FieldValue.serverTimestamp(),
      });
      await Future.delayed(const Duration(milliseconds: 150));
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur envoi: $e'),
          backgroundColor: const Color(0xFF8B4513),
        ));
        _ctrl.text = texte;
      }
    }
  }

  static const _workerUrl = 'https://ecomap-upload.bastienbouchard.workers.dev';

  Future<void> _envoyerPhoto() async {
    final bytes = await pickPhoto();
    if (bytes == null || bytes.isEmpty) return;

    final idToken = await AuthService.getIdToken();
    if (idToken == null) return;

    setState(() => _envoyantPhoto = true);
    try {
      final filename = '${widget.groupeId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final resp = await http.post(
        Uri.parse(_workerUrl),
        headers: {
          'Content-Type': 'image/jpeg',
          'Authorization': 'Bearer $idToken',
          'X-Filename': filename,
        },
        body: bytes,
      );
      if (resp.statusCode != 200) throw Exception('Upload échoué: ${resp.statusCode} — ${resp.body}');
      final url = (json.decode(resp.body) as Map)['url'] as String;

      await _db
          .collection('groupes')
          .doc(widget.groupeId)
          .collection('messages')
          .add({
        'nom': widget.monNom,
        'texte': '',
        'photoUrl': url,
        'ts': FieldValue.serverTimestamp(),
      });
      await Future.delayed(const Duration(milliseconds: 150));
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur photo: $e'),
          backgroundColor: const Color(0xFF8B4513),
        ));
      }
    } finally {
      if (mounted) setState(() => _envoyantPhoto = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Row(children: [
          const Icon(Icons.people, color: Color(0xFF4A90E2), size: 18),
          const SizedBox(width: 8),
          Text(widget.groupeId,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        iconTheme: const IconThemeData(color: Color(0xFFFF6B35)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messages,
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Erreur Firestore:\n${snap.error}',
                          style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 12),
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF4A90E2)));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text('Aucun message — commencez la discussion!',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final nom = d['nom'] as String? ?? '';
                    final texte = d['texte'] as String? ?? '';
                    final photoUrl = d['photoUrl'] as String?;
                    final ts = (d['ts'] as Timestamp?)?.toDate();
                    final estMoi = nom == widget.monNom;
                    final heure = ts != null
                        ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
                        : '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment:
                            estMoi ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!estMoi)
                            Container(
                              width: 30, height: 30,
                              margin: const EdgeInsets.only(right: 6, bottom: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A90E2).withOpacity(0.2),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF4A90E2), width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  nom.isNotEmpty ? nom[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                      color: Color(0xFF4A90E2), fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: estMoi
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (!estMoi)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2, left: 2),
                                    child: Text(nom,
                                        style: const TextStyle(
                                            color: Color(0xFF4A90E2),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                Container(
                                  padding: photoUrl != null
                                      ? const EdgeInsets.all(4)
                                      : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: estMoi
                                        ? const Color(0xFF2D5016)
                                        : const Color(0xFF2D2D2D),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(14),
                                      topRight: const Radius.circular(14),
                                      bottomLeft: Radius.circular(estMoi ? 14 : 4),
                                      bottomRight: Radius.circular(estMoi ? 4 : 14),
                                    ),
                                    border: Border.all(
                                      color: estMoi
                                          ? const Color(0xFF5A8A1E).withOpacity(0.4)
                                          : Colors.white12,
                                    ),
                                  ),
                                  child: photoUrl != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.network(
                                            photoUrl,
                                            width: 220,
                                            fit: BoxFit.cover,
                                            loadingBuilder: (_, child, progress) => progress == null
                                                ? child
                                                : SizedBox(
                                                    width: 220, height: 140,
                                                    child: Center(child: CircularProgressIndicator(
                                                      value: progress.expectedTotalBytes != null
                                                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                                          : null,
                                                      color: const Color(0xFF4A90E2),
                                                    )),
                                                  ),
                                          ),
                                        )
                                      : Text(texte,
                                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                                  child: Text(heure,
                                      style: const TextStyle(color: Colors.white24, fontSize: 10)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 16 + MediaQuery.of(context).viewPadding.bottom),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(children: [
              // Bouton photo
              GestureDetector(
                onTap: _envoyantPhoto ? null : _envoyerPhoto,
                child: Container(
                  width: 42, height: 42,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: _envoyantPhoto
                      ? const Center(child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4A90E2))))
                      : const Icon(Icons.photo_outlined, color: Colors.white54, size: 22),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _envoyer(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _envoyer,
                child: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D5016),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF5A8A1E).withOpacity(0.5)),
                  ),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
