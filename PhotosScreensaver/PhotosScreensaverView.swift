import QuartzCore
import ScreenSaver

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

  override init?(frame: NSRect, isPreview: Bool) {
    super.init(frame: frame, isPreview: isPreview)
    setUp()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setUp()
  }

  deinit {
    accessedFolder?.stopAccessingSecurityScopedResource()
  }

  private func setUp() {
    // Make this a layer-hosting view. All drawing happens in sublayers.
    let rootLayer = CALayer()
    rootLayer.backgroundColor = NSColor.black.cgColor
    rootLayer.masksToBounds = true
    layer = rootLayer
    wantsLayer = true

    // Transitions are driven by Core Animation. The frame callback only needs
    // to check whether it's time for the next photo.
    animationTimeInterval = 0.25
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

  override func animateOneFrame() {
    showPreloadedPhotoIfDue()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for sublayer in layer?.sublayers ?? [] {
      sublayer.bounds = CGRect(origin: .zero, size: newSize)
      sublayer.position = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
    }
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

    guard let folder = settings.folderURL else {
      return
    }
    if folder.startAccessingSecurityScopedResource() {
      accessedFolder = folder
    }

    let generation = self.generation
    loadQueue.async { [weak self] in
      let urls = PhotoScanner.photos(in: folder)
      DispatchQueue.main.async {
        guard let self, self.generation == generation else {
          return
        }
        self.photos = ShuffledQueue(urls)
        self.preloadNextPhoto()
      }
    }
  }

  private func stopSlideshow() {
    isRunning = false
    generation += 1
    isLoading = false
    consecutiveLoadFailures = 0
    preloadedImage = nil
    photos = ShuffledQueue([])
    currentPhotoLayer = nil

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
    loadQueue.async { [weak self] in
      let image = ImageLoader.loadImage(
        at: url,
        filling: targetSize,
        maxZoom: KenBurnsMotion.maxZoom
      )
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
    let controller = ConfigureSheetController(settings: settings) { [weak self] in
      self?.restartSlideshow()
    }
    configureSheetController = controller
    return controller.window
  }
}
