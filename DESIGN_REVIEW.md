# macOS design review

Reviewed against Apple’s macOS Human Interface Guidelines and SwiftUI
documentation on 20 September 2026:

- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Menus](https://developer.apple.com/design/human-interface-guidelines/menus)

## Findings

The app already has several good macOS conventions: menu-bar commands, a
Settings scene that enables the standard Settings menu item, keyboard
shortcuts, native SwiftUI controls, and a restrained utility-window layout.

The main improvement to consider is removing the gear button from the main
window toolbar. Apple’s macOS guidance says Settings should be available from
the App menu and that toolbar space should be reserved for essential commands.
The existing menu-bar Settings command is sufficient, so the toolbar gear is
redundant. This was documented rather than changed in this resource-efficiency
branch because removing it would alter an existing shortcut to a frequently
used command without a dedicated UI regression pass.

The refresh, direct-selection, and pin actions are appropriate toolbar actions;
they are task-specific and remain useful when the window is open. They should
also remain available through the menu bar or keyboard shortcuts, which the
current app already does for the core pin/unpin actions.

No ornamental visual effects were added. The capture path is performance
sensitive, and the existing translucent/window-cover treatment should be
validated visually on macOS 26 before introducing newer materials or animation.
