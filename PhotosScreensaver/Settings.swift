import Foundation
import OSLog
import ScreenSaver

private let logger = Logger(subsystem: Logger.subsystem, category: "Settings")

/// The user's settings, stored with `ScreenSaverDefaults` so they end up in
/// the screensaver host's sandbox container.
final class Settings {
  static let delayRange: ClosedRange<TimeInterval> = 5...600
  static let defaultDelay: TimeInterval = 30

  #if DEBUG
    /// Used in Debug builds when no folder has been chosen, to make testing
    /// from Xcode quicker.
    private static let debugFolderPath =
      "/Users/janaagaard/Developer/GitHub/developer-quotes-wallpapers/wallpapers/3840x2160"
  #endif

  private static let delayKey = "delay"
  private static let folderBookmarkKey = "folderBookmark"
  private static let folderPathKey = "folderPath"

  private let defaults: UserDefaults

  init() {
    let moduleName =
      Bundle(for: Settings.self).bundleIdentifier ?? "net.aagaard.PhotosScreensaver"
    defaults = ScreenSaverDefaults(forModuleWithName: moduleName) ?? .standard
  }

  /// Seconds between the start of one transition and the start of the next.
  var delay: TimeInterval {
    get {
      let stored = defaults.double(forKey: Self.delayKey)
      guard stored > 0 else {
        return Self.defaultDelay
      }
      return min(max(stored, Self.delayRange.lowerBound), Self.delayRange.upperBound)
    }
    set {
      logger.info("Saved delay \(newValue) s")
      defaults.set(newValue, forKey: Self.delayKey)
      defaults.synchronize()
    }
  }

  /// The folder to show photos from. Resolved from a security-scoped bookmark
  /// when possible, so access survives the sandbox, with the plain path as a
  /// fallback.
  var folderURL: URL? {
    if let bookmark = defaults.data(forKey: Self.folderBookmarkKey) {
      var isStale = false
      if let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) {
        return url
      }
      if let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: [],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) {
        return url
      }
      logger.error("Could not resolve the folder bookmark, falling back to the stored path")
    }

    if let path = defaults.string(forKey: Self.folderPathKey) {
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    #if DEBUG
      return URL(fileURLWithPath: Self.debugFolderPath, isDirectory: true)
    #else
      return nil
    #endif
  }

  func setFolderURL(_ url: URL) {
    var bookmark = try? url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    if bookmark == nil {
      logger.notice("Could not create a security-scoped bookmark, using a plain bookmark")
      bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    if bookmark == nil {
      logger.error("Could not create a bookmark, storing only the path")
    }
    logger.info("Saved folder \(url.path, privacy: .public)")
    defaults.set(bookmark, forKey: Self.folderBookmarkKey)
    defaults.set(url.path, forKey: Self.folderPathKey)
    defaults.synchronize()
  }
}
