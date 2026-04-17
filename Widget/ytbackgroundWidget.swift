import ActivityKit
import SwiftUI
import WidgetKit

struct PlaybackLiveActivityView: View {
    let state: PlaybackActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(state.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: state.progress)
                    .tint(.orange)
            }

            Spacer(minLength: 8)

            Image(systemName: state.isPlaying ? "waveform" : "pause.circle")
                .font(.title3)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var artworkURL: URL? {
        guard let artworkURLString = state.artworkURLString else { return nil }
        return URL(string: artworkURLString)
    }
}

struct PlaybackLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            PlaybackLiveActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.circle")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.channelTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress)
                        .tint(.orange)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.circle")
            } compactTrailing: {
                Text(progressLabel(for: context.state.progress))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.circle")
            }
        }
    }

    private func progressLabel(for progress: Double) -> String {
        "\(Int(progress * 100))%"
    }
}

@main
struct ytbackgroundWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaybackLiveActivityWidget()
    }
}
