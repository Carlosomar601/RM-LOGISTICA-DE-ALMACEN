/// Variante visual semántica (badges, pills, chips).
enum Tone { good, warn, crit, neutral, accent }

/// Badge de antigüedad: ≥45 crit, 20–44 warn, <20 good.
Tone ageTone(int days) {
  if (days >= 45) return Tone.crit;
  if (days >= 20) return Tone.warn;
  return Tone.good;
}
