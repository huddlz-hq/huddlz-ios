import XCTest

extension XCUIElement {
    /// Taps a field and types once it really has keyboard focus. A tap that lands while the keyboard
    /// or a sheet is still animating can leave focus on the previous field, and typing then fails with
    /// "Neither element nor any descendant has keyboard focus". Tap again, up to three times, until focus arrives.
    @MainActor
    func typeAfterFocusing(_ text: String) {
        let hasFocus = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 {
            tap()
            // An expectation can be waited on only once, so each attempt gets its own.
            let focused = XCTNSPredicateExpectation(predicate: hasFocus, object: self)
            if XCTWaiter.wait(for: [focused], timeout: 2) == .completed { break }
        }
        typeText(text)
    }
}
