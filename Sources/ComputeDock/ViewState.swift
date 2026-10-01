import SwiftUI

// Explicitly use the property wrapper, including on SDKs that also offer a
// same-named State macro. This keeps Command Line Tools builds self-contained.
typealias ViewState<Value> = SwiftUI.State<Value>
