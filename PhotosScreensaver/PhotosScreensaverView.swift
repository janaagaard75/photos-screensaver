import OSLog
import QuartzCore
import ScreenSaver

private let logger = Logger(subsystem: Logger.subsystem, category: "Slideshow")

@objc(PhotosScreensaverView)
final class PhotosScreensaverView: ScreenSaverView {
  private static let fadeDuration: CFTimeInterval = 2

  private let settings = Settings()
  private var configureSheetController: ConfigureSheetController?

  private let loadQueue = DispatchQueue(
    label: "net.aagaard.PhotosScreensaver.load",
    qos: .userInitiated
  )

  private var isRunning = false
  /// Incremented whenever the slideshow is stopped, so results from background
  /// work started before that are ignored.
  private var generation = 0
  private var delay = Settings.defaultDelay
  private var accessedFolder: URL?
  private var photos = ShuffledQueue<URL>([])
  private var isLoading = false
  private var consecutiveLoadFailures = 0
  private var preloadedImage: CGImage?
  private var nextTransitionTime: CFTimeInterval = 0
  private var currentPhotoLayer: CALayer?
  private var messageLayer: CATextLayer?

  override init?(frame: NSRect, isPreview: Bool) {
    super.init(frame: frame, isPreview: isPreview)
    setUp()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  deinit {
    DistributedNotificationCenter.default().removeObserver(self)
    accessedFolder?.stopAccessingSecurityScopedResource()
  }

  private func setUp() {
    logger.info("Created view (preview: \(self.isPreview), size: \(Double(self.frame.width)) x \(Double(self.frame.height)))")

    // Make this a layer-hosting view. All drawing happens in sublayers.
    let rootLayer = CALayer()
    rootLayer.backgroundColor = NSColor.black.cgColor
    rootLayer.masksToBounds = true
    layer = rootLayer
    wantsLayer = true

    // Transitions are driven by Core Animation. The frame callback only needs
    // to check whether it's time for the next photo.
    animationTimeInterval = 0.25

    // Since macOS 14, the screensaver host often doesn't call stopAnimation()
    // and keeps old instances alive, so they would go on decoding photos in
    // the background. Stop explicitly when the screensaver is dismissed.
    if !isPreview {
      DistributedNotificationCenter.default().addObserver(
        self,
        selector: #selector(screensaverWillStop),
        name: Notification.Name("com.apple.screensaver.willstop"),
        object: nil
      )
    }
  }

  // MARK: Screensaver life cycle

  override func startAnimation() {
    super.startAnimation()
    startSlideshow()
  }

  override func stopAnimation() {
    super.stopAnimation()
    stopSlideshow()
  }

  @objc private func screensaverWillStop(_ notification: Notification) {
    logger.info("Received willstop notification")
    stopSlideshow()
  }

  override func animateOneFrame() {
    showPreloadedPhotoIfDue()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in layer?.sublayers ?? [] where sublayer !== messageLayer {
      sublayer.bounds = CGRect(origin: .zero, size: newSize)
      sublayer.position = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
    }
    layoutMessageLayer(in: newSize)
    CATransaction.commit()
  }

  // MARK: Slideshow

  private func startSlideshow() {
    guard !isRunning else {
      return
    }
    isRunning = true
    delay = settings.delay
    nextTransitionTime = 0
    logger.info("Starting slideshow (preview: \(self.isPreview), delay: \(self.delay) s)")

    guard let folder = settings.folderURL else {
      logger.notice("No photo folder has been chosen")
      showMessage("No photo folder has been chosen.")
      return
    }
    if folder.startAccessingSecurityScopedResource() {
      accessedFolder = folder
    }
    logger.info(
      "Scanning \(folder.path, privacy: .public) (security-scoped access: \(self.accessedFolder != nil))"
    )

    let generation = self.generation
    loadQueue.async { [weak self] in
      let scanStart = Date()
      let urls = PhotoScanner.photos(in: folder)
      let scanDuration = Date().timeIntervalSince(scanStart)
      logger.info("Found \(urls.count) photos in \(scanDuration, format: .fixed(precision: 2)) s")
      DispatchQueue.main.async {
        guard let self, self.generation == generation else {
          return
        }
        guard !urls.isEmpty else {
          self.showMessage(Self.emptyFolderProblem(folder))
          return
        }
        self.photos = ShuffledQueue(urls)
        self.preloadNextPhoto()
      }
    }
  }

  private func stopSlideshow() {
    if isRunning {
      logger.info("Stopping slideshow (preview: \(self.isPreview))")
    }
    isRunning = false
    generation += 1
    isLoading = false
    consecutiveLoadFailures = 0
    preloadedImage = nil
    photos = ShuffledQueue([])
    currentPhotoLayer = nil
    messageLayer = nil

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
    CATransaction.commit()

    accessedFolder?.stopAccessingSecurityScopedResource()
    accessedFolder = nil
  }

  private func restartSlideshow() {
    guard isRunning else {
      return
    }
    logger.info("Settings changed, restarting slideshow")
    stopSlideshow()
    startSlideshow()
  }

  /// Decodes the next photo in the background, so it's ready when it's time to
  /// show it.
  private func preloadNextPhoto() {
    guard !isLoading, preloadedImage == nil, let url = photos.next() else {
      return
    }
    isLoading = true

    let generation = self.generation
    let targetSize = pixelSize
    let folderPath = accessedFolder?.path ?? settings.folderURL?.path ?? ""

    loadQueue.async { [weak self] in
      let loadStart = Date()
      let image = ImageLoader.loadImage(
        at: url,
        filling: targetSize,
        maxZoom: KenBurnsMotion.maxZoom
      )
      let loadMilliseconds = Int(Date().timeIntervalSince(loadStart) * 1000)
      if let image {
        logger.debug(
          "Decoded \(url.lastPathComponent, privacy: .public) at \(image.width) x \(image.height) in \(loadMilliseconds) ms"
        )
      } else {
        logger.error("Could not decode \(url.path, privacy: .public)")
      }
      DispatchQueue.main.async {
        guard let self, self.generation == generation else {
          return
        }
        self.isLoading = false
        if let image {
          self.consecutiveLoadFailures = 0
          self.preloadedImage = image
          self.showPreloadedPhotoIfDue()
        } else {
          // Skip unreadable files, but stop once every photo has failed.
          self.consecutiveLoadFailures += 1
          if self.consecutiveLoadFailures < self.photos.count {
            self.preloadNextPhoto()
          } else if self.currentPhotoLayer == nil {
            logger.error("None of the photos could be decoded")
            self.showMessage("None of the photos in “\(folderPath)” could be opened.")
          }
        }
      }
    }
  }

  private func showPreloadedPhotoIfDue() {
    let now = CACurrentMediaTime()
    guard let image = preloadedImage, now >= nextTransitionTime else {
      return
    }
    preloadedImage = nil
    show(image)
    nextTransitionTime = now + delay
    preloadNextPhoto()
  }

  /// Fades in a new layer with the photo on top of the current one, and
  /// removes the old layer once it's fully covered.
  private func show(_ image: CGImage) {
    guard let rootLayer = layer else {
      return
    }
    let size = rootLayer.bounds.size
    let motion = KenBurnsMotion.random(for: size)

    let photoLayer = CALayer()
    photoLayer.contents = image
    photoLayer.contentsGravity = .resizeAspectFill
    photoLayer.bounds = CGRect(origin: .zero, size: size)
    photoLayer.position = CGPoint(x: size.width / 2, y: size.height / 2)
    photoLayer.transform = motion.endTransform

    // Keep moving until this photo has been completely covered by the next
    // one, with some slack in case the next photo is slow to load.
    let zoom = CABasicAnimation(keyPath: "transform")
    zoom.fromValue = NSValue(caTransform3D: motion.startTransform)
    zoom.toValue = NSValue(caTransform3D: motion.endTransform)
    zoom.duration = delay + 2 * Self.fadeDuration
    zoom.timingFunction = CAMediaTimingFunction(name: .linear)

    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = Self.fadeDuration
    fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rootLayer.addSublayer(photoLayer)
    photoLayer.add(zoom, forKey: "kenBurns")
    photoLayer.add(fade, forKey: "fadeIn")
    CATransaction.commit()

    let previousLayer = currentPhotoLayer
    currentPhotoLayer = photoLayer
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      previousLayer?.removeFromSuperlayer()
      CATransaction.commit()
    }
  }

  // MARK: Messages

  private static func emptyFolderProblem(_ folder: URL) -> String {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
    if exists && isDirectory.boolValue {
      return "No JPEG, PNG or HEIC photos were found in “\(folder.path)”."
    } else {
      return "The folder “\(folder.path)” could not be opened."
    }
  }

  /// Shows a centered message explaining why there are no photos to show.
  private func showMessage(_ problem: String) {
    guard let rootLayer = layer else {
      return
    }
    let textLayer = messageLayer ?? CATextLayer()
    textLayer.string = problem + "\n\nOpen Screen Saver Options to choose a folder."
    textLayer.isWrapped = true
    textLayer.alignmentMode = .center
    textLayer.foregroundColor = NSColor(white: 1, alpha: 0.7).cgColor
    textLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    messageLayer = textLayer

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if textLayer.superlayer == nil {
      rootLayer.addSublayer(textLayer)
    }
    layoutMessageLayer(in: bounds.size)
    CATransaction.commit()
  }

  /// Sizes the font to the view, so the message is readable both in the small
  /// preview and full screen, and centers the text vertically.
  private func layoutMessageLayer(in size: CGSize) {
    guard let messageLayer, let message = messageLayer.string as? String else {
      return
    }
    let fontSize = max(10, size.height / 40)
    let font = NSFont.systemFont(ofSize: fontSize)
    messageLayer.font = font
    messageLayer.fontSize = fontSize

    let width = size.width * 0.8
    let textHeight = (message as NSString).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin],
      attributes: [.font: font]
    ).height
    messageLayer.bounds = CGRect(x: 0, y: 0, width: width, height: ceil(textHeight))
    messageLayer.position = CGPoint(x: size.width / 2, y: size.height / 2)
  }

  /// The size of the view in pixels, used to decode photos at the right size.
  private var pixelSize: CGSize {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    return CGSize(width: bounds.width * scale, height: bounds.height * scale)
  }

  // MARK: Options sheet

  override var hasConfigureSheet: Bool {
    true
  }

  override var configureSheet: NSWindow? {
    // Reuse the controller. Its buttons only hold weak references to it, so
    // replacing it would break a window that is already on screen.
    if let controller = configureSheetController {
      if !controller.window.isVisible {
        controller.loadSettings()
      }
      return controller.window
    }
    let controller = ConfigureSheetController(settings: settings) { [weak self] in
      self?.restartSlideshow()
    }
    configureSheetController = controller
    return controller.window
  }
}
