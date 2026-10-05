import CoreGraphics
import Foundation
import ImageIO

enum ImageLoader {
  /// Decodes the photo at `url`, rotated according to its EXIF orientation and
  /// downsampled so that it just covers `targetPixelSize` when scaled to fill
  /// and zoomed by `maxZoom`. Decoding a 50 MP photo at full size for a 5K
  /// screen would waste both time and memory.
  static func loadImage(at url: URL, filling targetPixelSize: CGSize, maxZoom: CGFloat) -> CGImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
      CGImageSourceGetCount(source) > 0
    else {
      return nil
    }

    var options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    if let size = orientedPixelSize(of: source), size.width > 0, size.height > 0 {
      let fillScale = max(
        targetPixelSize.width / size.width,
        targetPixelSize.height / size.height
      ) * maxZoom
      let longestSide = max(size.width, size.height)
      // Never upscale; the layer will do that if needed.
      options[kCGImageSourceThumbnailMaxPixelSize] = min(longestSide, ceil(longestSide * fillScale))
    }

    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// The pixel size of the image after applying its EXIF orientation.
  private static func orientedPixelSize(of source: CGImageSource) -> CGSize? {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue
    else {
      return nil
    }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    // Orientations 5-8 are rotated by 90 degrees.
    let isRotated = (5...8).contains(orientation)
    return isRotated ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }
}
