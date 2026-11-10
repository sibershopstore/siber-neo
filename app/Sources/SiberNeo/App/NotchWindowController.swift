import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Manages the overlay window in the notch area: position, hover hit-testing, and open/close.
@MainActor
final class NotchWindowController {
    static let canvasSize = CGSize(width: 920, height: 360)

    private let state: NotchState
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var closeWork: DispatchWorkItem?
    private var screenFrame: CGRect = .zero

    /// Horizontal cursor position relative to the screen (-1 left, 1 right), used for the mascot's eyes.
    var onMouseActivity: ((CGFloat) -> Void)?
    /// Called when the notch opens.
    var onOpen: (() -> Void)?

    init(state: NotchState, rootView: AnyView) {
        self.state = state
        panel = NotchPanel(
            contentRect: CGRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: Self.canvasSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        layout()
        panel.orderFrontRegardless()
        installMonitors()
        installObservers()
    }

    // MARK: - Layout

    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func layout() {
        guard let screen = Self.targetScreen() else { return }
        screenFrame = screen.frame

        let size = Self.canvasSize
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)

        let topInset = screen.safeAreaInsets.top
        if topInset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            state.notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: topInset)
            state.hasNotch = true
        } else {
            let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            state.notchSize = CGSize(width: 180, height: menuBar)
            state.hasNotch = false
        }
    }

    // MARK: - Mouse tracking

    private func installMonitors() {
        let globalMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, isLocal: false) }
        }) {
            monitors.append(monitor)
        }

        let localMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: localMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, isLocal: true) }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseKeepOpen() }
        })
    }

    private func handle(_ event: NSEvent, isLocal: Bool) {
        let point = NSEvent.mouseLocation
        let inside = hitRect().contains(point)
        if event.type != .leftMouseDown, screenFrame.width > 0 {
            onMouseActivity?((point.x - screenFrame.midX) / (screenFrame.width / 2))
        }
        panel.ignoresMouseEvents = !inside

        if event.type == .leftMouseDown, !isLocal, !inside {
            releaseKeepOpen()
            return
        }

        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !state.isOpen {
                open()
            }
            if event.type == .leftMouseDragged, Self.dragHasFiles() {
                state.tab = .shelf
            }
        } else if state.isOpen, !state.keepOpen, closeWork == nil {
            scheduleClose()
        }
    }

    private func hitRect() -> CGRect {
        let size = state.currentSize
        var rect = CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if !state.isOpen {
            rect = rect.insetBy(dx: -6, dy: 0)
            rect.origin.y -= 6
            rect.size.height += 6
        }
        return rect
    }

    private static func dragHasFiles() -> Bool {
        NSPasteboard(name: .drag).types?.contains(.fileURL) ?? false
    }

    // MARK: - Open / close

    private func open() {
        state.isOpen = true
        onOpen?()
        UISound.open.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func scheduleClose() {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.closeIfOutside() }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func closeIfOutside() {
        closeWork = nil
        guard !state.keepOpen, !hitRect().contains(NSEvent.mouseLocation) else { return }
        state.isOpen = false
        state.isDropTargeted = false
        panel.ignoresMouseEvents = true
    }

    private func releaseKeepOpen() {
        guard state.keepOpen else { return }
        state.keepOpen = false
        if state.isOpen, closeWork == nil {
            scheduleClose()
        }
    }
}
