import QuartzCore
import ScreenSaver

@objc(PhotosScreensaverView)
final class PhotosScreensaverView: ScreenSaverView {
  private let settings = Settings()
  private var configureSheetController: ConfigureSheetController?

  override init?(frame: NSRect, isPreview: Bool) {
    super.init(frame: frame, isPreview: isPreview)
    setUp()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  private func setUp() {
    // Make this a layer-hosting view. All drawing happens in sublayers.
    let rootLayer = CALayer()
    rootLayer.backgroundColor = NSColor.black.cgColor
    rootLayer.masksToBounds = true
    layer = rootLayer
    wantsLayer = true
  }

  // MARK: Options sheet

  override var hasConfigureSheet: Bool {
    true
  }

  override var configureSheet: NSWindow? {
    let controller = ConfigureSheetController(settings: settings)
    configureSheetController = controller
    return controller.window
  }
}
