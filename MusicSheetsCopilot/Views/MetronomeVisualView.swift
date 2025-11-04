import SwiftUI

struct MetronomeVisualView: View {
    @ObservedObject var metronome: Metronome

    var body: some View {
        if metronome.isEnabled && metronome.isTicking {
            HStack(spacing: 4) {
                ForEach(0..<metronome.timeSignature.0, id: \.self) { beat in
                    BeatBar(isActive: beat == metronome.currentBeat)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .transition(.opacity.combined(with: .scale))
        }
    }
}

struct BeatBar: View {
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 30, height: 8)
            .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}
