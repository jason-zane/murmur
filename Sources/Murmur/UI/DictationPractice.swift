import SwiftUI

/// The same capture pipeline as global dictation, with a local, disposable destination.
struct DictationPractice: View {
    @Bindable var controller: DictationController
    @State private var result = ""
    @State private var attempted = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.md) {
                Text("Try dictation").font(DS.Font.headline).foregroundStyle(DS.Color.text)
                Spacer()
                ActionButton(title: controller.isPractising ? "Stop" : "Try dictation",
                             systemImage: controller.isPractising ? "stop.fill" : "mic", emphasis: .normal) {
                    if controller.isPractising { controller.stopPractice() }
                    else {
                        attempted = true
                        controller.startPractice { result = $0 }
                    }
                }
                .disabled(PreviewEnvironment.isActive || (controller.state.isActive && !controller.isPractising) || controller.state == .finishing)
            }
            Hint("Say: Send it Tuesday, actually Wednesday. Your cleaned text appears here. Microphone access is requested when you try it.")
            Text(result.isEmpty ? (controller.isPractising ? "Listening…" : "Your words will appear here.") : result)
                .font(DS.Font.body).foregroundStyle(result.isEmpty ? DS.Color.textSecondary : DS.Color.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: DS.Layout.practiceHeight, alignment: .topLeading)
                .padding(DS.Space.md)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.sm))
                .accessibilityLabel("Practice dictation result")
            if attempted, let message = controller.lastError { InlineNotice(text: message, tone: .warning) }
            Hint("Only text is kept in this field. Practice is not added to dictation history.")
        }
        .onDisappear { controller.cancelPractice() }
    }
}
