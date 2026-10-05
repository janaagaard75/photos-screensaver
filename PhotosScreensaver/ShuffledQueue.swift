/// Hands out the elements in random order. Every element is returned once
/// before the elements are reshuffled, and the same element is never returned
/// twice in a row.
struct ShuffledQueue<Element: Equatable> {
  private let elements: [Element]
  private var remaining: [Element] = []
  private var lastReturned: Element?

  init(_ elements: [Element]) {
    self.elements = elements
  }

  var isEmpty: Bool {
    elements.isEmpty
  }

  var count: Int {
    elements.count
  }

  mutating func next() -> Element? {
    if remaining.isEmpty {
      remaining = elements.shuffled()
      // Elements are popped from the end, so make sure the next one isn't the
      // one that was just shown.
      if remaining.count > 1, remaining.last == lastReturned {
        remaining.swapAt(0, remaining.count - 1)
      }
    }
    let element = remaining.popLast()
    lastReturned = element
    return element
  }
}
