import SwiftUI

struct EditorView: View {
    @ObservedObject var controller: PrompterController
    @FocusState private var editing: Bool

    private let canvas = Color(red: 0.060, green: 0.051, blue: 0.098)
    private let surface = Color(red: 0.087, green: 0.076, blue: 0.134)
    private let violet = Color(red: 0.73, green: 0.60, blue: 1.0)
    private let blue = Color(red: 0.49, green: 0.66, blue: 1.0)
    private let muted = Color.white.opacity(0.55)
    private let border = Color.white.opacity(0.105)

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            header
            scriptToolbar
            scriptEditor
            controls
        }
        .padding(.horizontal, 32)
        .padding(.top, 42)
        .padding(.bottom, 23)
        .frame(minWidth: 590, minHeight: 470)
        .foregroundStyle(Color.white.opacity(0.93))
        .background {
            canvas
                .overlay {
                    RadialGradient(
                        colors: [violet.opacity(0.18), .clear],
                        center: .topLeading, startRadius: 12, endRadius: 440
                    )
                }
                .overlay {
                    RadialGradient(
                        colors: [blue.opacity(0.10), .clear],
                        center: .bottomTrailing, startRadius: 8, endRadius: 340
                    )
                }
                .ignoresSafeArea()
        }
        .tint(violet)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(violet.opacity(0.15))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(violet.opacity(0.29))
                    }
                CameraCueMark()
                    .stroke(violet, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 13)
            }
            .frame(width: 39, height: 39)
            .accessibilityHidden(true)

            Text("Camera Cue")
                .font(.system(size: 27, weight: .semibold))
                .tracking(-1.05)
                .accessibilityAddTraits(.isHeader)

            Spacer()
            status
        }
        .padding(.bottom, 12)
    }

    private var status: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(controller.mode == .listening ? violet : .white.opacity(0.28))
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 2 }
                .accessibilityHidden(true)
            Text(controller.status)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(muted)
        .frame(maxWidth: 250, alignment: .trailing)
    }

    private var scriptToolbar: some View {
        HStack(spacing: 10) {
            Text("Script")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if controller.mode != .idle {
                Text("Cue \(controller.cueIndex + 1) of \(controller.cueCount)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted)
            }
            Spacer()
            Menu {
                ForEach(PrompterController.Language.allCases) { language in
                    Button(language.label) { controller.loadSample(language) }
                }
            } label: {
                Label("Load sample", systemImage: "doc.plaintext")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(controller.mode != .idle)
        }
    }

    private var scriptEditor: some View {
        ZStack(alignment: .topLeading) {
            if controller.script.isEmpty {
                Text("Paste or type a script…")
                    .font(.system(size: 19))
                    .foregroundStyle(muted)
                    .padding(.leading, 23)
                    .padding(.top, 20)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $controller.script)
                .font(.system(size: 19))
                .lineSpacing(9)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .focused($editing)
                .disabled(controller.mode != .idle)
                .accessibilityLabel("Teleprompter script")
        }
        .frame(minHeight: 195)
        .background(surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .strokeBorder(editing && controller.mode == .idle ? violet.opacity(0.60) : border)
                .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 10) {
            languagePicker
            Spacer(minLength: 12)

            Button {
                editing = false
                if controller.mode == .idle {
                    controller.preview()
                } else {
                    controller.close()
                }
            } label: {
                Label(
                    controller.mode == .idle ? "Preview island" : "Close island",
                    systemImage: controller.mode == .idle ? "eye" : "xmark"
                )
            }
            .buttonStyle(CueEditorButton(violet: violet, blue: blue, primary: false))
            .disabled(!controller.canStart)
            .help(controller.mode == .idle ? "Try the camera island with the microphone off." : "Close the camera island.")

            Button {
                editing = false
                controller.primaryAction()
            } label: {
                Label(controller.primaryTitle, systemImage: controller.mode == .listening ? "pause.fill" : "mic.fill")
            }
            .buttonStyle(CueEditorButton(violet: violet, blue: blue, primary: true))
            .disabled(!controller.canStart)
        }
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Speech language")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(muted)
                .accessibilityHidden(true)
            Picker("Speech language", selection: $controller.language) {
                ForEach(PrompterController.Language.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)
            .disabled(controller.mode != .idle)
        }
    }
}

private struct CameraCueMark: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.midX
        let y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: y))
        path.addLine(to: CGPoint(x: x - 7, y: y))
        path.addQuadCurve(to: CGPoint(x: x - 4, y: y + 3), control: CGPoint(x: x - 5, y: y))
        path.addLine(to: CGPoint(x: x - 3, y: y + 5))
        path.addQuadCurve(to: CGPoint(x: x, y: y + 7), control: CGPoint(x: x - 2, y: y + 7))
        path.addQuadCurve(to: CGPoint(x: x + 3, y: y + 5), control: CGPoint(x: x + 2, y: y + 7))
        path.addLine(to: CGPoint(x: x + 4, y: y + 3))
        path.addQuadCurve(to: CGPoint(x: x + 7, y: y), control: CGPoint(x: x + 5, y: y))
        path.addLine(to: CGPoint(x: rect.maxX - 1, y: y))
        path.move(to: CGPoint(x: x - 4, y: rect.maxY))
        path.addLine(to: CGPoint(x: x + 4, y: rect.maxY))
        return path
    }
}

private struct CueEditorButton: ButtonStyle {
    let violet: Color
    let blue: Color
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .foregroundStyle(primary ? Color(red: 0.07, green: 0.048, blue: 0.14) : .white.opacity(0.92))
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: primary ? [violet, blue] : [violet.opacity(0.13), blue.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(primary ? 0.15 : 0.10))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(!isEnabled ? 0.40 : configuration.isPressed ? 0.76 : 1)
    }
}
