import QuartzCore

/// A slow zoom in or out combined with a small pan, from one random framing of
/// the photo to another.
struct KenBurnsMotion {
  static let maxZoom: CGFloat = 1.15

  private static let zoomedOutRange: ClosedRange<CGFloat> = 1.02...1.05
  private static let zoomedInRange: ClosedRange<CGFloat> = 1.11...maxZoom

  let startTransform: CATransform3D
  let endTransform: CATransform3D

  /// A random motion for a layer of the given size, anchored at its center.
  static func random(for size: CGSize) -> KenBurnsMotion {
    let zoomedOut = CGFloat.random(in: zoomedOutRange)
    let zoomedIn = CGFloat.random(in: zoomedInRange)
    let zoomsIn = Bool.random()
    return KenBurnsMotion(
      startTransform: framing(scale: zoomsIn ? zoomedOut : zoomedIn, size: size),
      endTransform: framing(scale: zoomsIn ? zoomedIn : zoomedOut, size: size)
    )
  }

  /// Scales the layer around its center and moves it to a random offset. The
  /// offset is limited so the edges of the layer never come into view.
  private static func framing(scale: CGFloat, size: CGSize) -> CATransform3D {
    let maxOffsetX = (scale - 1) * size.width / 2
    let maxOffsetY = (scale - 1) * size.height / 2
    let offsetX = CGFloat.random(in: -1...1) * maxOffsetX
    let offsetY = CGFloat.random(in: -1...1) * maxOffsetY
    return CATransform3DConcat(
      CATransform3DMakeScale(scale, scale, 1),
      CATransform3DMakeTranslation(offsetX, offsetY, 0)
    )
  }
}
