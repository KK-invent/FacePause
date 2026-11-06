import SwiftUI

// Select the property wrapper explicitly: the macOS 27 SDK also exports a
// same-named macro whose plugin is not bundled with Command Line Tools.
typealias LocalViewState<Value> = SwiftUI.State<Value>
