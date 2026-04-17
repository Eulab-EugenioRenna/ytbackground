import SwiftUI

struct YouTubeWebPlayerView: View {
    let player: YouTubePlayer

    var body: some View {
        YouTubePlayerView(player) { state in
            switch state {
            case .idle:
                ZStack {
                    Color.black
                    ProgressView()
                        .tint(.white)
                }
            case .ready:
                EmptyView()
            case .error:
                ZStack {
                    Color.black
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
