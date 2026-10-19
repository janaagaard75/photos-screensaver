import QuartzCore

/// A slow zoom in or out combined with a small pan, from one random framing of
/// the photo to another.
struct KenBurnsMotion {
  static let maxZoom: CGFloat = 1.08

  private static let zoomedOutRange: ClosedRange<CGFloat> = 1.02...1.03
  private static let zoomedInRange: ClosedRange<CGFloat> = 1.06...maxZoom

  /// How far the framing may move during the motion, as a fraction of the
  /// largest offset that keeps the edges of the layer out of view.
  private static let maxPan: CGFloat = 0.5

  let startTransform: CATransform3D
  let endTransform: CATransform3D

  /// A random motion for a layer of the given size, anchored at its center.
  static func random(for size: CGSize) -> KenBurnsMotion {
    let zoomedOut = CGFloat.random(in: zoomedOutRange)
    let zoomedIn = CGFloat.random(in: zoomedInRange)
    let zoomsIn = Bool.random()

    // Offsets range from -1 to 1, where ±1 puts an edge of the photo at the
    // edge of the screen.
    let startOffset = CGPoint(x: CGFloat.random(in: -1...1), y: CGFloat.random(in: -1...1))
    let endOffset = CGPoint(
      x: (startOffset.x + CGFloat.random(in: -maxPan...maxPan)).clamped(to: -1...1),
      y: (startOffset.y + CGFloat.random(in: -maxPan...maxPan)).clamped(to: -1...1)
    )

    return KenBurnsMotion(
      startTransform: framing(scale: zoomsIn ? zoomedOut : zoomedIn, offset: startOffset, size: size),
      endTransform: framing(scale: zoomsIn ? zoomedIn : zoomedOut, offset: endOffset, size: size)
    )
  }

  /// Scales the layer around its center and moves it by the given offset. The
  /// offset is relative to the scale so the edges of the layer never come into
  /// view.
  private static func framing(scale: CGFloat, offset: CGPoint, size: CGSize) -> CATransform3D {
    let maxOffsetX = (scale - 1) * size.width / 2
    let maxOffsetY = (scale - 1) * size.height / 2
    return CATransform3DConcat(
      CATransform3DMakeScale(scale, scale, 1),
      CATransform3DMakeTranslation(offset.x * maxOffsetX, offset.y * maxOffsetY, 0)
    )
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
