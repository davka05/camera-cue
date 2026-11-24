import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class PrompterPanel: NSObject {
    private let content = PrompterContent()
    private var isPresented = false
    private var presentationID = 0

    private lazy var window: CameraPanel = {
        let panel = CameraPanel(
            contentRect: NSRect(x: 0, y: 0, width: 464, height: 134),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Camera Cue Overlay"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = PanelHostingView(rootView: CameraPromptView(content: content))
        return panel
    }()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func present(
        lines: [String],
        index: Int,
        progress: Double,
        isPaused: Bool,
        onMove: @escaping (Int) -> Void,
        onTogglePause: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        guard lines.indices.contains(index) else {
            dismiss()
            return
        }
        let text = PrompterContent.TextState(
            lines: lines,
            index: index,
            progress: progress.isFinite ? min(max(progress, 0), 1) : 0,
            isPaused: isPaused
        )
        if text != content.text {
            let distance = abs(text.rollPosition - content.text.rollPosition)
            content.rollDuration = min(1.05, 0.42 + 0.17 * distance)
            content.animatesRoll = isPresented && content.text.lines == lines
            content.text = text
        }
        content.onMove = onMove
        content.onTogglePause = onTogglePause
        content.onClose = onClose

        guard !isPresented else { return }
        isPresented = true
        presentationID += 1
        positionWindow()
        window.ignoresMouseEvents = false
        window.orderFrontRegardless()

        let ticket = presentationID
        Task { @MainActor [weak self] in
            guard let self, self.presentationID == ticket else { return }
            self.animate(expanded: true, ticket: ticket)
        }
    }

    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        presentationID += 1
        window.ignoresMouseEvents = true
        content.onMove = nil
        content.onTogglePause = nil
        content.onClose = nil
        animate(expanded: false, ticket: presentationID)
    }

    @objc private func screenParametersChanged() {
        if isPresented { positionWindow() }
    }

    private func animate(expanded: Bool, ticket: Int) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: expanded ? 0.34 : 0.24)
        withAnimation(animation, completionCriteria: .removed) {
            content.isExpanded = expanded
        } completion: { [weak self] in
            guard let self, self.presentationID == ticket else { return }
            if expanded {
                self.window.invalidateShadow()
            } else {
                self.window.orderOut(nil)
            }
        }
    }

    private func positionWindow() {
        let builtIn = NSScreen.screens.first { screen in
            guard let identifier = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(identifier.uint32Value) != 0
        }
        guard let screen = builtIn ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let safeInset = screen.safeAreaInsets.top
        let leftEdge = screen.auxiliaryTopLeftArea?.maxX
        let rightEdge = screen.auxiliaryTopRightArea?.minX
        let width = min(464, screen.frame.width - 16)
        let height: CGFloat = 134
        var center = screen.frame.midX
        var top = screen.visibleFrame.maxY
        var neckWidth: CGFloat = 132

        if safeInset > 0, let leftEdge, let rightEdge, rightEdge > leftEdge {
            center = (leftEdge + rightEdge) / 2
            top = screen.frame.maxY - safeInset + 4
            neckWidth = rightEdge - leftEdge - 10
            window.level = .statusBar
        } else {
            window.level = .floating
        }

        // Keep the bars of the menu outside the island's narrow attachment.
        content.neckWidth = min(max(neckWidth, 56), width - 64)
        let scale = screen.backingScaleFactor
        let left = ((center - width / 2) * scale).rounded() / scale
        let alignedTop = (top * scale).rounded() / scale
        window.setFrame(NSRect(x: left, y: alignedTop - height, width: width, height: height), display: true)
        window.invalidateShadow()
    }
}

private final class CameraPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The transparent shoulders cross a few points of the menu bar so the stem can enter the notch.
        frameRect
    }
}

private final class PanelHostingView: NSHostingView<CameraPromptView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class PrompterContent: ObservableObject {
    struct TextState: Equatable {
        var lines: [String] = []
        var index = 0
        var progress: Double = 0
        var isPaused = false

        var hasNext: Bool { lines.indices.contains(index + 1) }
        var current: String { lines.indices.contains(index) ? lines[index] : "" }
        var position: String { "\(index + 1) / \(lines.count)" }

        var rollPosition: Double {
            // Let a spoken cue drift upward while leaving enough room to read its last words.
            Double(index) + (hasNext ? 0.48 * progress : 0)
        }
    }

    @Published var text = TextState()
    @Published var neckWidth: CGFloat = 175
    @Published var isExpanded = false
    var animatesRoll = false
    var rollDuration: Double = 0.42
    var onMove: ((Int) -> Void)?
    var onTogglePause: (() -> Void)?
    var onClose: (() -> Void)?
}

private struct CameraPromptView: View {
    @ObservedObject var content: PrompterContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let violet = Color(red: 0.70, green: 0.58, blue: 1)
    private let periwinkle = Color(red: 0.46, green: 0.52, blue: 1)
    private let panelBottom = Color(red: 0.065, green: 0.052, blue: 0.13)

    var body: some View {
        let shape = CameraIslandShape(neckWidth: content.neckWidth, expansion: content.isExpanded ? 1 : 0)

        ZStack(alignment: .top) {
            shape
                .fill(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0.17), .init(color: panelBottom, location: 1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RadialGradient(
                        colors: [periwinkle.opacity(0.22), violet.opacity(0.06), .clear],
                        center: .bottom, startRadius: 2, endRadius: 233
                    )
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0.28), .init(color: .white, location: 1)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(shape)
                }
                .overlay {
                    shape.stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.17),
                                .init(color: violet.opacity(0.10), location: 0.62),
                                .init(color: periwinkle.opacity(0.46), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
                .accessibilityHidden(true)

            VStack(spacing: 1) {
                cueViewport
                controls
            }
            .padding(.horizontal, 23)
            .padding(.top, 17)
            .opacity(content.isExpanded ? 1 : 0)
            .mask(shape)
            .allowsHitTesting(content.isExpanded)
            .accessibilityHidden(!content.isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var cueViewport: some View {
        let position = reduceMotion ? Double(content.text.index) : content.text.rollPosition
        return CueStrip(lines: content.text.lines, rollPosition: position)
            .frame(height: 83)
            .clipped()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.075),
                        .init(color: .white, location: 0.24),
                        .init(color: .white, location: 0.86),
                        .init(color: .white.opacity(0.70), location: 0.94),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .animation(
                reduceMotion || !content.animatesRoll ? nil : .smooth(duration: content.rollDuration),
                value: position
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current cue, \(content.text.current)")
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 3) {
                iconButton("chevron.up", label: "Previous cue", enabled: content.text.index > 0) {
                    content.onMove?(-1)
                }
                iconButton(
                    content.text.isPaused ? "play.fill" : "pause.fill",
                    label: content.text.isPaused ? "Start following" : "Pause following",
                    primary: true
                ) { content.onTogglePause?() }
                iconButton("chevron.down", label: "Next cue", enabled: content.text.hasNext) {
                    content.onMove?(1)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(violet.opacity(0.12), in: Capsule())

            HStack {
                Text(content.text.position)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(violet.opacity(0.88))
                    .accessibilityLabel("Cue \(content.text.position)")
                Spacer()
                iconButton("xmark", label: "Close prompter") { content.onClose?() }
            }
        }
        .frame(height: 28)
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        enabled: Bool = true,
        primary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(primary ? Color(red: 0.08, green: 0.045, blue: 0.20) : .white.opacity(enabled ? 0.82 : 0.27))
                .frame(width: primary ? 32 : 25, height: 23)
                .background {
                    if primary {
                        Capsule().fill(
                            LinearGradient(colors: [violet, periwinkle], startPoint: .leading, endPoint: .trailing)
                        )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct CueStrip: View, Animatable {
    let lines: [String]
    var rollPosition: Double

    var animatableData: Double {
        get { rollPosition }
        set { rollPosition = newValue }
    }

    private let linePitch: CGFloat = 37
    private let readingCenter: CGFloat = 33

    var body: some View {
        GeometryReader { geometry in
            ForEach(visibleLines, id: \.self) { index in
                let offset = CGFloat(Double(index) - rollPosition)
                let emphasis = max(0, 1 - abs(offset))
                Text(lines[index])
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.35)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 1))
                    .lineLimit(2)
                    .minimumScaleFactor(0.71)
                    .frame(width: max(0, geometry.size.width - 18), height: 43)
                    .scaleEffect(0.86 + 0.14 * emphasis)
                    .opacity(0.55 + 0.45 * Double(emphasis))
                    .position(
                        x: geometry.size.width / 2,
                        y: readingCenter + offset * linePitch
                    )
            }
        }
    }

    private var visibleLines: Range<Int> {
        // Render only rows around the animation's current position, including during long jumps.
        let anchor = Int(rollPosition.rounded(.down))
        let first = min(max(anchor - 2, 0), lines.count)
        let end = max(first, min(lines.count, anchor + 4))
        return first..<end
    }
}

private struct CameraIslandShape: Shape {
    let neckWidth: CGFloat
    var expansion: CGFloat

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = min(max(expansion, 0), 1)
        let middle = rect.midX
        let neck = min(neckWidth, rect.width - 2) / 2
        let halfBody = neck + (rect.width / 2 - neck - 1) * progress
        let topRight = middle + neck
        let topLeft = middle - neck
        let right = middle + halfBody
        let left = middle - halfBody
        let top = rect.minY
        let shoulder = top + 17 * progress
        let bottom = top + 1 + (rect.height - 2) * progress
        let outerCurve = min(23 * progress, (halfBody - neck) / 2)
        let flare = min(30 * progress, max(0, halfBody - neck - outerCurve))
        let lowerCurve = 24 * progress

        var path = Path()
        path.move(to: CGPoint(x: topLeft, y: top))
        path.addLine(to: CGPoint(x: topRight, y: top))
        path.addCurve(
            to: CGPoint(x: topRight + flare, y: shoulder),
            control1: CGPoint(x: topRight + flare * 0.36, y: top + 2 * progress),
            control2: CGPoint(x: topRight + flare * 0.39, y: shoulder)
        )
        path.addLine(to: CGPoint(x: right - outerCurve, y: shoulder))
        path.addQuadCurve(to: CGPoint(x: right, y: shoulder + outerCurve), control: CGPoint(x: right, y: shoulder))
        path.addLine(to: CGPoint(x: right, y: bottom - lowerCurve))
        path.addQuadCurve(to: CGPoint(x: right - lowerCurve, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + lowerCurve, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - lowerCurve), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: shoulder + outerCurve))
        path.addQuadCurve(to: CGPoint(x: left + outerCurve, y: shoulder), control: CGPoint(x: left, y: shoulder))
        path.addLine(to: CGPoint(x: topLeft - flare, y: shoulder))
        path.addCurve(
            to: CGPoint(x: topLeft, y: top),
            control1: CGPoint(x: topLeft - flare * 0.39, y: shoulder),
            control2: CGPoint(x: topLeft - flare * 0.36, y: top + 2 * progress)
        )
        path.closeSubpath()
        return path
    }
}
