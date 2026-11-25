/// Raw touch input model for the Gesture Recognizer (design: `GestureSample`).
/// Plain Dart: no Flutter dependencies.
library;

/// One finger contact at a point in time.
final class Finger {
  final int id;
  final double x;
  final double y;
  const Finger(this.id, this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is Finger && other.id == id && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(id, x, y);
}

/// A snapshot of all fingers currently touching the surface.
/// An empty [fingers] list means every finger has been lifted.
final class GestureSample {
  final List<Finger> fingers;
  final DateTime timestamp;
  const GestureSample(this.fingers, this.timestamp);
}
