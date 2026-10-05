import AppKit

/// The panel shown when clicking "Options…" in System Settings.
final class ConfigureSheetController: NSObject {
  /// The delays the slider can snap to, in seconds.
  private static let delaySteps: [TimeInterval] = [
    5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 450, 600,
  ]

  let window: NSWindow

  private let settings: Settings
  private let onSave: () -> Void
  private var selectedFolder: URL?

  private let folderLabel = NSTextField(labelWithString: "")
  private let delaySlider = NSSlider()
  private let delayLabel = NSTextField(labelWithString: "")

  private let delayFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = .full
    return formatter
  }()

  init(settings: Settings, onSave: @escaping () -> Void = {}) {
    self.settings = settings
    self.onSave = onSave
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
      styleMask: [.titled],
      backing: .buffered,
      defer: true
    )
    super.init()
    // The window is owned by this controller. Without this, closing it would
    // release it a second time.
    window.isReleasedWhenClosed = false
    buildContent()
    loadSettings()
  }

  private func buildContent() {
    folderLabel.lineBreakMode = .byTruncatingMiddle
    folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    folderLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

    let chooseButton = NSButton(
      title: "Choose…",
      target: self,
      action: #selector(chooseFolder)
    )

    delaySlider.minValue = 0
    delaySlider.maxValue = Double(Self.delaySteps.count - 1)
    delaySlider.numberOfTickMarks = Self.delaySteps.count
    delaySlider.allowsTickMarkValuesOnly = true
    delaySlider.target = self
    delaySlider.action = #selector(delayChanged)

    delayLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

    let grid = NSGridView(views: [
      [NSTextField(labelWithString: "Photo folder:"), folderLabel, chooseButton],
      [NSTextField(labelWithString: "Time per photo:"), delaySlider, delayLabel],
    ])
    grid.rowSpacing = 12
    grid.columnSpacing = 8
    grid.column(at: 0).xPlacement = .trailing
    grid.rowAlignment = .firstBaseline

    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    cancelButton.keyEquivalent = "\u{1b}"
    let okButton = NSButton(title: "OK", target: self, action: #selector(save))
    okButton.keyEquivalent = "\r"

    let buttons = NSStackView(views: [cancelButton, okButton])
    buttons.orientation = .horizontal
    buttons.spacing = 12

    let content = NSStackView(views: [grid, buttons])
    content.orientation = .vertical
    content.alignment = .trailing
    content.spacing = 20
    content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    content.translatesAutoresizingMaskIntoConstraints = false

    let contentView = NSView()
    contentView.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      content.topAnchor.constraint(equalTo: contentView.topAnchor),
      content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])
    window.contentView = contentView
  }

  /// Shows the stored settings, discarding any unsaved changes.
  func loadSettings() {
    selectedFolder = settings.folderURL
    updateFolderLabel()

    let delay = settings.delay
    let nearestIndex =
      Self.delaySteps.indices.min { abs(Self.delaySteps[$0] - delay) < abs(Self.delaySteps[$1] - delay) }
      ?? 0
    delaySlider.integerValue = nearestIndex
    updateDelayLabel()
  }

  private var selectedDelay: TimeInterval {
    let index = min(max(delaySlider.integerValue, 0), Self.delaySteps.count - 1)
    return Self.delaySteps[index]
  }

  private func updateFolderLabel() {
    folderLabel.stringValue = selectedFolder?.path ?? "None"
    folderLabel.toolTip = selectedFolder?.path
  }

  private func updateDelayLabel() {
    delayLabel.stringValue = delayFormatter.string(from: selectedDelay) ?? ""
  }

  @objc private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    panel.message = "Choose a folder with photos. Subfolders are included."
    panel.directoryURL = selectedFolder
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let url = panel.url, let self else {
        return
      }
      self.selectedFolder = url
      self.updateFolderLabel()
    }
  }

  @objc private func delayChanged() {
    updateDelayLabel()
  }

  @objc private func cancel() {
    close()
  }

  @objc private func save() {
    if let selectedFolder, selectedFolder != settings.folderURL {
      settings.setFolderURL(selectedFolder)
    }
    settings.delay = selectedDelay
    close()
    onSave()
  }

  private func close() {
    if let parent = window.sheetParent {
      parent.endSheet(window)
    } else {
      window.close()
    }
  }
}
