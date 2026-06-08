import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MeteoPage extends StatefulWidget {
  final double latitude;
  final double longitude;
  final double? windDeg;
  final double? windSpeed;

  const MeteoPage({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.windDeg,
    required this.windSpeed,
  });

  @override
  State<MeteoPage> createState() => _MeteoPageState();
}

class _MeteoPageState extends State<MeteoPage> {
  List<Map<String, dynamic>> _forecast = [];
  bool _loadingForecast = true;

  @override
  void initState() {
    super.initState();
    _fetchForecast();
  }

  Future<void> _fetchForecast() async {
    try {
      final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${widget.latitude}'
        '&longitude=${widget.longitude}'
        '&daily=wind_speed_10m_max,wind_direction_10m_dominant,'
        'temperature_2m_max,temperature_2m_min,precipitation_sum,'
        'cloud_cover_mean,sunrise,sunset'
        '&timezone=auto'
        '&forecast_days=4',
      );
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map;
        final daily = data['daily'] as Map;
        final times = daily['time'] as List;
        final List<Map<String, dynamic>> forecast = [];
        for (int i = 0; i < times.length; i++) {
          forecast.add({
            'date': times[i] as String,
            'windSpeed': (daily['wind_speed_10m_max'][i] as num?)?.toDouble() ?? 0.0,
            'windDir': (daily['wind_direction_10m_dominant'][i] as num?)?.toDouble() ?? 0.0,
            'tempMax': (daily['temperature_2m_max'][i] as num?)?.toDouble() ?? 0.0,
            'tempMin': (daily['temperature_2m_min'][i] as num?)?.toDouble() ?? 0.0,
            'precip': (daily['precipitation_sum'][i] as num?)?.toDouble() ?? 0.0,
            'cloud': (daily['cloud_cover_mean'][i] as num?)?.toInt() ?? 0,
            'sunrise': daily['sunrise'][i] as String?,
            'sunset': daily['sunset'][i] as String?,
          });
        }
        if (mounted) setState(() { _forecast = forecast; _loadingForecast = false; });
      } else {
        if (mounted) setState(() => _loadingForecast = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingForecast = false);
    }
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';

  String _windDir(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return dirs[((deg + 22.5) / 45).floor() % 8];
  }

  String _countdown(Duration d) {
    if (d.isNegative) return '';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  String _dayLabel(String dateStr, int index) {
    if (index == 0) return "Auj.";
    if (index == 1) return "Demain";
    final dt = DateTime.parse(dateStr);
    const days = ['Dim', 'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];
    return days[dt.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime? sunrise, sunset;
    if (_forecast.isNotEmpty) {
      sunrise = _forecast[0]['sunrise'] != null
          ? DateTime.tryParse(_forecast[0]['sunrise'] as String)
          : null;
      sunset = _forecast[0]['sunset'] != null
          ? DateTime.tryParse(_forecast[0]['sunset'] as String)
          : null;
    }
    final legalStart = sunrise?.subtract(const Duration(minutes: 30));
    final legalEnd = sunset?.add(const Duration(minutes: 30));

    Duration? nextChange;
    String nextLabel = '';
    if (legalStart != null && now.isBefore(legalStart)) {
      nextChange = legalStart.difference(now);
      nextLabel = 'Début de la chasse dans';
    } else if (legalEnd != null && now.isBefore(legalEnd)) {
      nextChange = legalEnd.difference(now);
      nextLabel = 'Fin de la chasse dans';
    } else if (_forecast.length > 1 && _forecast[1]['sunrise'] != null) {
      final tmSr = DateTime.tryParse(_forecast[1]['sunrise'] as String);
      if (tmSr != null) {
        nextChange = tmSr.subtract(const Duration(minutes: 30)).difference(now);
        nextLabel = 'Début de la chasse demain dans';
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        title: const Text('Météo', style: TextStyle(color: Colors.white)),
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
          // ── VENT ACTUEL ────────────────────────────────────────
          _card(children: [
            _sectionTitle('Vent actuel'),
            const SizedBox(height: 12),
            if (widget.windDeg != null && widget.windSpeed != null) ...[
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Transform.rotate(
                  angle: (widget.windDeg! + 180) * pi / 180,
                  child: const Icon(Icons.navigation, color: Color(0xFF87CEEB), size: 48),
                ),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  '${_windDir(widget.windDeg!)}  —  ${widget.windSpeed!.toStringAsFixed(0)} km/h',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ]),
            ] else
              const Center(child: Text('Données vent indisponibles',
                  style: TextStyle(color: Colors.white54))),
          ]),

          const SizedBox(height: 12),

          // ── PHASE LUNAIRE ──────────────────────────────────────
          _card(children: [
            _sectionTitle('Phase lunaire'),
            const SizedBox(height: 12),
            _moonCard(),
          ]),

          const SizedBox(height: 12),

          // ── PRÉVISIONS 3 JOURS ─────────────────────────────────
          _card(children: [
            _sectionTitle('Prévisions — 3 prochains jours'),
            const SizedBox(height: 12),
            if (_loadingForecast)
              const Center(child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Color(0xFFFF6B35), strokeWidth: 2),
              ))
            else if (_forecast.isEmpty)
              const Center(child: Text('Prévisions indisponibles',
                  style: TextStyle(color: Colors.white54)))
            else
              Row(
                children: _forecast.asMap().entries.map((e) {
                  final i = e.key;
                  final f = e.value;
                  final isToday = i == 0;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < _forecast.length - 1 ? 6 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isToday
                            ? const Color(0xFF2D5016).withOpacity(0.4)
                            : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isToday
                              ? const Color(0xFF5A8A1E).withOpacity(0.6)
                              : const Color(0xFF3D3D3D),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(_dayLabel(f['date'] as String, i),
                              style: TextStyle(
                                color: isToday ? const Color(0xFF7DC95E) : Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              )),
                          const SizedBox(height: 6),
                          Transform.rotate(
                            angle: ((f['windDir'] as double) + 180) * pi / 180,
                            child: Icon(Icons.navigation,
                                color: const Color(0xFF87CEEB),
                                size: 20),
                          ),
                          const SizedBox(height: 2),
                          Text('${_windDir(f['windDir'] as double)}',
                              style: const TextStyle(color: Color(0xFF87CEEB), fontSize: 10)),
                          Text('${(f['windSpeed'] as double).toStringAsFixed(0)} km/h',
                              style: const TextStyle(color: Colors.white70, fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('${(f['tempMax'] as double).toStringAsFixed(0)}°',
                              style: const TextStyle(color: Colors.white, fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          Text('${(f['tempMin'] as double).toStringAsFixed(0)}°',
                              style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          const SizedBox(height: 4),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(
                              (f['cloud'] as int) < 25
                                  ? Icons.wb_sunny
                                  : (f['cloud'] as int) < 60
                                      ? Icons.wb_cloudy
                                      : Icons.cloud,
                              color: (f['cloud'] as int) < 25
                                  ? const Color(0xFFFFD700)
                                  : (f['cloud'] as int) < 60
                                      ? Colors.white54
                                      : Colors.white38,
                              size: 11,
                            ),
                            const SizedBox(width: 2),
                            Text('${f['cloud']}%',
                                style: TextStyle(
                                  color: (f['cloud'] as int) < 25
                                      ? const Color(0xFFFFD700)
                                      : Colors.white38,
                                  fontSize: 9,
                                )),
                          ]),
                          if ((f['precip'] as double) > 0.5) ...[
                            const SizedBox(height: 2),
                            Text('💧 ${(f['precip'] as double).toStringAsFixed(0)} mm',
                                style: const TextStyle(color: Colors.white38, fontSize: 9)),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ]),

          const SizedBox(height: 12),

          // ── CHASSE LÉGALE ──────────────────────────────────────
          _card(children: [
            _sectionTitle('Heures légales de chasse'),
            const SizedBox(height: 4),
            const Text(
              'La chasse débute ½h avant le lever du soleil et se termine ½h après le coucher.',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 14),
            if (sunrise != null && legalStart != null)
              _timeRow('🌅', 'Lever du soleil', _fmt(sunrise),
                  'Début légal (½h avant)', _fmt(legalStart)),
            const SizedBox(height: 12),
            if (sunset != null && legalEnd != null)
              _timeRow('🌇', 'Coucher du soleil', _fmt(sunset),
                  'Fin légale (½h après)', _fmt(legalEnd)),
            if (nextChange != null) ...[
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.timer_outlined, color: Color(0xFFFF6B35), size: 15),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  '$nextLabel ${_countdown(nextChange)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                )),
              ]),
            ],
          ]),

          const SizedBox(height: 12),

          _card(children: [
            _sectionTitle('Réglementation au Québec'),
            const SizedBox(height: 8),
            const Text(
              'La chasse est permise de ½ heure avant le lever du soleil jusqu\'à ½ heure après le coucher du soleil.\n\nCes heures sont calculées pour votre position GPS actuelle.',
              style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
            ),
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

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 13,
            fontWeight: FontWeight.bold, letterSpacing: 0.5));
  }

  Widget _moonCard() {
    final ref = DateTime.utc(2000, 1, 6, 18, 14);
    final age = DateTime.now().toUtc().difference(ref).inSeconds / 86400.0 % 29.53059;
    final illum = ((1 - cos(2 * pi * age / 29.53059)) / 2 * 100).round();

    String emoji, name, tip;
    Color tipColor;
    int score;

    if (age < 1.85) {
      emoji = '🌑'; name = 'Nouvelle lune';
      tip = 'Orignaux très actifs de jour — conditions idéales';
      tipColor = const Color(0xFF7DC95E); score = 5;
    } else if (age < 7.38) {
      emoji = '🌒'; name = 'Premier croissant';
      tip = 'Bonne activité diurne — profitez du matin';
      tipColor = const Color(0xFF7DC95E); score = 4;
    } else if (age < 11.08) {
      emoji = '🌓'; name = 'Premier quartier';
      tip = 'Activité mixte — la matinée reste favorable';
      tipColor = const Color(0xFFFF6B35); score = 3;
    } else if (age < 14.77) {
      emoji = '🌔'; name = 'Lune croissante';
      tip = 'Orignaux plus nocturnes — activité réduite le jour';
      tipColor = Colors.white54; score = 2;
    } else if (age < 16.61) {
      emoji = '🌕'; name = 'Pleine lune';
      tip = 'Nocturne — les orignaux bougent peu de jour';
      tipColor = Colors.white38; score = 1;
    } else if (age < 22.15) {
      emoji = '🌖'; name = 'Lune décroissante';
      tip = 'Activité en hausse — orignaux actifs en soirée';
      tipColor = Colors.white54; score = 2;
    } else if (age < 25.84) {
      emoji = '🌗'; name = 'Dernier quartier';
      tip = 'Bonne activité diurne — en amélioration';
      tipColor = const Color(0xFFFF6B35); score = 3;
    } else {
      emoji = '🌘'; name = 'Dernier croissant';
      tip = 'Très bonne activité diurne — conditions favorables';
      tipColor = const Color(0xFF7DC95E); score = 4;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Illumination : $illum %',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              Row(children: List.generate(5, (i) => Icon(
                i < score ? Icons.star_rounded : Icons.star_outline_rounded,
                color: i < score ? const Color(0xFFFF6B35) : const Color(0xFF3D3D3D),
                size: 16,
              ))),
            ],
          )),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: illum / 100,
            backgroundColor: const Color(0xFF3D3D3D),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE8D5A3)),
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: tipColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tipColor.withOpacity(0.3)),
          ),
          child: Row(children: [
            _MooseTrackIcon(color: tipColor, size: 14),
            const SizedBox(width: 8),
            Expanded(child: Text(tip,
                style: TextStyle(color: tipColor, fontSize: 12, height: 1.3))),
          ]),
        ),
      ],
    );
  }

  Widget _timeRow(String emoji, String label, String time, String legalLabel, String legalTime) {
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 24)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(time, style: const TextStyle(color: Colors.white, fontSize: 16,
              fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          Text(legalLabel, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const Spacer(),
          Text(legalTime, style: const TextStyle(color: Color(0xFFFF6B35), fontSize: 13,
              fontWeight: FontWeight.bold)),
        ]),
      ])),
    ]);
  }
}

class _MooseTrackIcon extends StatelessWidget {
  final Color color;
  final double size;
  const _MooseTrackIcon({required this.color, this.size = 14});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MooseTrackPainter(color: color)),
      );
}

class _MooseTrackPainter extends CustomPainter {
  final Color color;
  const _MooseTrackPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    // Deux sabots principaux (ongles du sabot fendu)
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.30, h * 0.58), width: w * 0.30, height: h * 0.52), p);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.70, h * 0.58), width: w * 0.30, height: h * 0.52), p);
    // Ergots (petits points au-dessus)
    canvas.drawCircle(Offset(w * 0.26, h * 0.18), w * 0.09, p);
    canvas.drawCircle(Offset(w * 0.74, h * 0.18), w * 0.09, p);
  }

  @override
  bool shouldRepaint(_MooseTrackPainter old) => old.color != color;
}
