/// Fuses Laplacian and EAR eye-state estimates into a single label.
class EyeStateCombiner {
  String combine(String laplacian, String ear) {
    if (laplacian == 'unknown' && ear == 'unknown') return 'unknown';
    if (laplacian == 'unknown') return ear;
    if (ear == 'unknown') return laplacian;
    if (laplacian == 'open' && ear == 'open') return 'open';
    if (laplacian == 'closed' && ear == 'closed') return 'closed';
    return 'closed';
  }

  (String, String) combinePair(
    (String, String) laplacian,
    (String, String) ear,
  ) {
    return (
      combine(laplacian.$1, ear.$1),
      combine(laplacian.$2, ear.$2),
    );
  }
}
