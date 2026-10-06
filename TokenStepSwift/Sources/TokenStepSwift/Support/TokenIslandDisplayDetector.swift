import AppKit

enum TokenIslandDisplayDetector {
    static var primaryScreen: NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
    }

    static var notchedPrimaryScreen: NSScreen? {
        guard let screen = primaryScreen, hasCameraHousing(on: screen) else {
            return nil
        }
        return screen
    }

    static var isAvailable: Bool {
        notchedPrimaryScreen != nil
    }

    static var fallbackReason: String {
        guard primaryScreen != nil else {
            return L("未检测到可用屏幕")
        }
        return L("当前主屏无刘海，已回到菜单栏")
    }

    static func isAvailable(for placement: TokenIslandDisplayPlacement, size: NSSize) -> Bool {
        guard placement != .menuBar,
              let screen = notchedPrimaryScreen
        else {
            return false
        }
        return collapsedFrame(on: screen, size: size, placement: placement) != nil
    }

    static func cameraHousingCenterX(on screen: NSScreen) -> CGFloat? {
        guard let areas = auxiliaryTopAreas(on: screen) else {
            return nil
        }

        let rawCenter = (areas.left.maxX + areas.right.minX) / 2
        if screen.frame.minX...screen.frame.maxX ~= rawCenter {
            return rawCenter
        }

        let screenRelativeCenter = screen.frame.minX + rawCenter
        if screen.frame.minX...screen.frame.maxX ~= screenRelativeCenter {
            return screenRelativeCenter
        }

        return nil
    }

    static func cameraHousingBottomY(on screen: NSScreen) -> CGFloat? {
        guard let areas = auxiliaryTopAreas(on: screen) else {
            return nil
        }

        let rawBottom = min(areas.left.minY, areas.right.minY)
        if screen.frame.minY...screen.frame.maxY ~= rawBottom {
            return rawBottom
        }

        let screenRelativeBottom = screen.frame.minY + rawBottom
        if screen.frame.minY...screen.frame.maxY ~= screenRelativeBottom {
            return screenRelativeBottom
        }

        return nil
    }

    static func collapsedFrame(on screen: NSScreen, size: NSSize, placement: TokenIslandDisplayPlacement) -> NSRect? {
        guard let areas = auxiliaryTopAreas(on: screen) else {
            return nil
        }

        let padding: CGFloat = 8
        let minimumWidth = size.width + padding * 2

        switch placement {
        case .menuBar:
            return nil
        case .automatic:
            if let left = collapsedFrame(in: areas.left, side: .left, size: size, padding: padding, minimumWidth: minimumWidth) {
                return left
            }
            return collapsedFrame(in: areas.right, side: .right, size: size, padding: padding, minimumWidth: minimumWidth)
        case .notchLeft:
            return collapsedFrame(in: areas.left, side: .left, size: size, padding: padding, minimumWidth: minimumWidth)
        case .notchRight:
            return collapsedFrame(in: areas.right, side: .right, size: size, padding: padding, minimumWidth: minimumWidth)
        }
    }

    private enum NotchSide {
        case left
        case right
    }

    private static func collapsedFrame(
        in area: NSRect,
        side: NotchSide,
        size: NSSize,
        padding: CGFloat,
        minimumWidth: CGFloat
    ) -> NSRect? {
        guard area.width >= minimumWidth else {
            return nil
        }
        let x: CGFloat
        switch side {
        case .left:
            x = max(area.minX + padding, area.maxX - size.width - padding)
        case .right:
            x = min(area.maxX - size.width - padding, area.minX + padding)
        }
        let y = area.midY - size.height / 2
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private static func hasCameraHousing(on screen: NSScreen) -> Bool {
        auxiliaryTopAreas(on: screen) != nil
    }

    private static func auxiliaryTopAreas(on screen: NSScreen) -> (left: NSRect, right: NSRect)? {
        if #available(macOS 12.0, *) {
            guard let leftArea = screen.auxiliaryTopLeftArea,
                  let rightArea = screen.auxiliaryTopRightArea
            else {
                return nil
            }
            guard !leftArea.isEmpty, !rightArea.isEmpty else {
                return nil
            }
            return (leftArea, rightArea)
        }
        return nil
    }
}
