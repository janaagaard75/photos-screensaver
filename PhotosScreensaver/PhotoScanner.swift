import Foundation

enum PhotoScanner {
  static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]

  /// Recursively finds all supported photos in `folder`, skipping hidden files
  /// and the insides of packages such as Photos libraries.
  static func photos(in folder: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      return []
    }

    var photos: [URL] = []
    for case let url as URL in enumerator {
      guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
        continue
      }
      guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
        continue
      }
      photos.append(url)
    }
    return photos
  }
}
