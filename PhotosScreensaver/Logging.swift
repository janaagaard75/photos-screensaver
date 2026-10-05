import OSLog

extension Logger {
  /// Shared by all log messages from the screensaver. Show them with:
  /// `log stream --level debug --predicate 'subsystem == "net.aagaard.PhotosScreensaver"'`
  static let subsystem = "net.aagaard.PhotosScreensaver"
}
