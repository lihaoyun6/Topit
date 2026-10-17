import AppKit

// Only the app's defaults and display conversion are required to link the renderer.
let ud = UserDefaults.standard
func CGRectTransform(cgRect: CGRect) -> NSRect { cgRect }
