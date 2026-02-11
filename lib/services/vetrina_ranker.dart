import 'dart:math';

class VetrinaRanker {
  VetrinaRanker._();

  static double score30d({
    required int visitors,
    required int observers,
    required int participants,
  }) {
    final mass = _log1(visitors) + 1.5 * _log1(observers);
    final quality = 2.0 * _log1(participants);
    return 0.55 * mass + 0.45 * quality;
  }

  static Map<String, dynamic> breakdown30d({
    required int visitors,
    required int observers,
    required int participants,
    required double conversionRate,
  }) {
    final massRaw = _log1(visitors) + 1.5 * _log1(observers);
    final qualityRaw = 2.0 * _log1(participants);
    final massScore = _toScore(massRaw, 4.0);
    final qualityScore = _toScore(qualityRaw, 3.0);
    final conversionScore = (conversionRate * 100).clamp(0, 100).toDouble();
    // Prioritize Mass (visits) over Quality and Conversion: 70-20-10
    final finalScore = 0.70 * massScore + 0.20 * qualityScore + 0.10 * conversionScore;

    final badges = <String>[];
    if (massScore >= 70) badges.add('High mass');
    if (qualityScore >= 70) badges.add('High quality');
    if (qualityScore <= 40) badges.add('Low quality');
    if (conversionScore <= 35) badges.add('Low conversion');
    if (conversionScore >= 70) badges.add('High conversion');

    return {
      'qualityScore30d': qualityScore,
      'massScore30d': massScore,
      'conversionScore30d': conversionScore,
      'finalScore30d': finalScore,
      'components': {
        'quality': _scoreText('Quality', qualityScore),
        'mass': _scoreText('Mass', massScore),
        'conversion': _scoreText('Conversion', conversionScore),
      },
      'badges': badges,
      'explanation': _explanation(qualityScore, massScore, conversionScore),
      'formulaVersion': 'v1',
    };
  }

  static double _log1(int v) {
    final n = v < 0 ? 0 : v;
    return log(n + 1.0);
  }

  static double _toScore(double raw, double k) {
    final score = (1 - exp(-raw / k)) * 100;
    if (score < 0) return 0;
    if (score > 100) return 100;
    return score;
  }

  static String _scoreText(String label, double score) {
    if (score >= 80) return '$label very high';
    if (score >= 60) return '$label good';
    if (score >= 40) return '$label medium';
    return '$label low';
  }

  static String _explanation(double quality, double mass, double conversion) {
    final qualityTag = quality >= 60 ? 'solid quality' : 'quality to improve';
    final massTag = mass >= 60 ? 'strong mass' : 'limited mass';
    final convTag = conversion >= 50 ? 'good conversion' : 'low conversion';
    return 'Showcase with $qualityTag, $massTag, and $convTag.';
  }
}
