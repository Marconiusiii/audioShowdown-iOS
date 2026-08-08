import SwiftUI

/// On-device readout of the live audio route.
///
/// The simulator cannot produce an AirPods route, so the one value that decides
/// whether the stereo field can be wide at all — the Bluetooth port type — can
/// only be observed on real hardware. `BluetoothHFP` is a **mono** transport:
/// iOS sums both channels onto it, so a puck panned hard left still arrives in
/// both ears. `BluetoothA2DP` is true stereo.
struct AudioDiagnosticsView: View {
    let theme: GameTheme
    let audioEngine: GameAudioEngine

    @State private var report = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeading(title: "Audio Diagnostics", theme: theme)
            Text(message)
                .font(.footnote)
                .foregroundStyle(theme.foreground)
                .textSelection(.enabled)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(message)
            Button("Read Audio Route") { report = audioEngine.routeDiagnostics() }
                .foregroundStyle(theme.accent)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var message: String {
        report.isEmpty ? "Connect your AirPods, then tap Read Audio Route." : report
    }
}
