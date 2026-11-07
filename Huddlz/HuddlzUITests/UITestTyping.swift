import XCTest

extension XCUIElement {
    /// Taps a field and types once it really has keyboard focus. A tap that lands while the keyboard
    /// or a sheet is still animating can leave focus on the previous field, and typing then fails with
    /// "Neither element nor any descendant has keyboard focus". Tap again, up to three times, until focus arrives.
    /// The field itself may appear late too: on a freshly booted hosted Simulator a sheet can take many
    /// seconds to present, so wait for the field before the first tap.
    @MainActor
    func typeAfterFocusing(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForExistence(timeout: 30), "\(self) never appeared", file: file, line: line)
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
