import ComposableArchitecture
import SwiftUI

struct BookSummary: Identifiable, Equatable {
    struct Chapter: Equatable {
        var title: String
        var audioFileName: String
        var duration: TimeInterval
    }

    var id: UUID = .init()
    var title: String
    var imageName: String
    var chapters: [Chapter]

    var purchaseId: String
}

extension BookSummary {
    static var mock: Self = BookSummary(
        id: UUID(0),
        title: "title",
        imageName: "book_cover",
        chapters: [
            .init(title: "Chapter 1. Some long text. Some long text. Some long text. Some long text. Some long text. Some long text", audioFileName: "summary_0", duration: 180),
            .init(title: "Chapter 2", audioFileName: "summary_1", duration: 102),
        ],
        purchaseId: "me.honcharenko.SummaryPlayerTCA.subscription"
    )
}

struct PlayerFeature: Reducer {
    struct State: Equatable {
        enum PlaybackSpeed: CaseIterable, Equatable {
            case x05
            case x075
            case x1
            case x15
            case x2

            var title: String {
                switch self {
                case .x05: return "x0.5"
                case .x075: return "x0.75"
                case .x1: return "x1"
                case .x15: return "x1.5"
                case .x2: return "x2"
                }
            }

            var speedMultiplier: Float {
                switch self {
                case .x05: return 0.5
                case .x075: return 0.75
                case .x1: return 1
                case .x15: return 1.5
                case .x2: return 1.99 // 2 is not working correctly
                }
            }
        }

        var bookSummary: BookSummary
        var currentChapterIndex: Int = 0
        var currentChapter: BookSummary.Chapter? {
            guard currentChapterIndex < bookSummary.chapters.count else { return nil }
            return bookSummary.chapters[currentChapterIndex]
        }

        var isPlaying: Bool = false
        var playbackPosition: PlaybackPosition
        var playbackSpeed: PlaybackSpeed = .x1

        init(bookSummary: BookSummary) {
            self.bookSummary = bookSummary
            if let firstChapter = bookSummary.chapters.first {
                playbackPosition = .init(currentTime: 0, duration: firstChapter.duration)
            } else {
                playbackPosition = .init(currentTime: 0, duration: 0)
            }
        }
    }

    enum Action: Equatable {
        case audioPlayerClient(PlaybackState)

        case playButtonTapped
        case pauseButtonTapped

        case fastForwardButtonTapped
        case rewindButtonTapped

        case progressSliderMoved(Double)

        case nextChapterButtonTapped
        case previousChapterButtonTapped

        case speedButtonTapped

        case updateChapterIfNeeded
    }

    @Dependency(\.audioPlayer) var audioPlayer
    @Dependency(\.continuousClock) var clock
    private enum CancelID { case play, seek }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .audioPlayerClient(playback):
                switch playback {                    
                case let .playing(position):
                    state.playbackPosition = position
                    return .send(.updateChapterIfNeeded, animation: .default)
                case let .pause(position):
                    state.playbackPosition = position
                    return .none
                case .stop:
                    return .none
                case let .error(message):
                    print("Playback error: \(message ?? "nil")")
                    return .none
                case .finish:
                    state.playbackPosition = .init(
                        currentTime: state.currentChapter?.duration ?? 0,
                        duration: state.currentChapter?.duration ?? 0
                    )
                    return .send(.updateChapterIfNeeded, animation: .default)
                }

            case .playButtonTapped:
                state.isPlaying = true

                return .run { [fileName = state.currentChapter?.audioFileName, playbackPosition = state.playbackPosition, speed = state.playbackSpeed] send in
                    let url = Bundle.main.url(forResource: fileName, withExtension: "mp3")!

                    for await playback in self.audioPlayer.play(playbackPosition, url, speed.speedMultiplier) {
                        await send(.audioPlayerClient(playback))
                    }
                }
                .cancellable(id: CancelID.play, cancelInFlight: true)

            case .pauseButtonTapped:
                state.isPlaying = false
                return .run { _ in
                    await audioPlayer.pause()
                }
                .merge(with: .cancel(id: CancelID.play))

            case .fastForwardButtonTapped:
                var playbackPosition = state.playbackPosition
                playbackPosition.currentTime += 10
                if playbackPosition.currentTime > playbackPosition.duration {
                    playbackPosition.currentTime = playbackPosition.duration
                }
                return .send(.progressSliderMoved(playbackPosition.progress))
            case .rewindButtonTapped:
                var playbackPosition = state.playbackPosition
                playbackPosition.currentTime -= 5
                if playbackPosition.currentTime < 0 {
                    playbackPosition.currentTime = 0
                }
                return .send(.progressSliderMoved(playbackPosition.progress))
            case let .progressSliderMoved(progress):
                var playbackPosition = state.playbackPosition
                playbackPosition.currentTime = progress * playbackPosition.duration
                state.playbackPosition = playbackPosition
                return .run { [playbackPosition] _ in
                    await audioPlayer.seekProgress(playbackPosition.progress)
                }
                .cancellable(id: CancelID.seek, cancelInFlight: true)
            case .nextChapterButtonTapped:
                state.playbackPosition = .init(
                    currentTime: state.currentChapter?.duration ?? 0,
                    duration: state.currentChapter?.duration ?? 0
                )
                return .send(.updateChapterIfNeeded)
            case .previousChapterButtonTapped:
                guard state.currentChapterIndex > 0 else { return .none }
                state.currentChapterIndex -= 1
                state.playbackPosition = .init(currentTime: 0, duration: state.currentChapter?.duration ?? 0)
                if state.isPlaying {
                    return .send(.playButtonTapped)
                }
                return .none
            case .speedButtonTapped:
                state.playbackSpeed = state.playbackSpeed == State.PlaybackSpeed.allCases.last
                    ? State.PlaybackSpeed.allCases.first!
                    : State.PlaybackSpeed.allCases.first { $0.speedMultiplier > state.playbackSpeed.speedMultiplier }!

                return .run { [speed = state.playbackSpeed.speedMultiplier] send in
                    await audioPlayer.speed(speed)
                }
            case .updateChapterIfNeeded:
                if state.playbackPosition.progress == 1 {
                    state.currentChapterIndex = (state.currentChapterIndex + 1) % state.bookSummary.chapters.count
                    if state.currentChapterIndex == 0 {
                        // stoping playback so summary is fully listened to
                        state.isPlaying = false
                    }
                    state.playbackPosition = .init(currentTime: 0, duration: state.currentChapter?.duration ?? 0)
                    if state.isPlaying {
                        return .send(.playButtonTapped)
                    }
                }

                return .none
            }
        }
    }
}

struct PlayerView: View {
    let store: StoreOf<PlayerFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            let duration = viewStore.state.playbackPosition.duration
            let currentTime = viewStore.state.playbackPosition.currentTime
            let timeLeft = viewStore.state.playbackPosition.duration - currentTime

            VStack(alignment: .center) {
                // MARK: - Book image

                Image(viewStore.bookSummary.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 65)

                Spacer()

                // MARK: - Chapter number

                Text("KEY POINT \(viewStore.currentChapterIndex + 1) OF \(viewStore.bookSummary.chapters.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(8)

                // MARK: - Chapter title

                Text(viewStore.currentChapter?.title ?? "")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(height: 65)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                // MARK: - Playback progress

                HStack(spacing: 12) {
                    dateComponentsFormatter.string(from: currentTime).map {
                        Text($0)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(Color(.systemGray))
                    }

                    Slider(
                        value: viewStore.binding(
                            get: { $0.playbackPosition.progress },
                            send: PlayerFeature.Action.progressSliderMoved
                        )
                    )
                    .disabled(duration == 0)

                    dateComponentsFormatter.string(from: timeLeft).map {
                        Text($0)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(Color(.systemGray))
                    }
                }
                .buttonStyle(.borderless)
                .padding()

                // MARK: - Speed button

                Button(action: {
                    viewStore.send(.speedButtonTapped)
                }, label: {
                    Text("Speed \(viewStore.state.playbackSpeed.title)")
                })
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .buttonStyle(.bordered)

                Spacer(minLength: 20)

                // MARK: - Playback controls

                HStack(spacing: 28) {
                    Button {
                        viewStore.send(.previousChapterButtonTapped)
                    } label: {
                        Image(systemName: "backward.end")
                            .font(.system(size: 32))
                    }
                    .tint(.primary)
                    .disabled(viewStore.currentChapterIndex == 0)

                    Button {
                        viewStore.send(.rewindButtonTapped)
                    } label: {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 32))
                    }
                    .tint(.primary)

                    Button {
                        if viewStore.state.isPlaying {
                            viewStore.send(.pauseButtonTapped)
                        } else {
                            viewStore.send(.playButtonTapped)
                        }
                    } label: {
                        Image(systemName: viewStore.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32))
                    }
                    .tint(.primary)

                    Button {
                        viewStore.send(.fastForwardButtonTapped)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 32))
                    }
                    .tint(.primary)

                    Button {
                        viewStore.send(.nextChapterButtonTapped)
                    } label: {
                        Image(systemName: "forward.end")
                            .font(.system(size: 32))
                    }
                    .tint(.primary)
                    .disabled(viewStore.currentChapterIndex == (viewStore.bookSummary.chapters.count - 1))
                }

                Spacer(minLength: 70)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview

#Preview {
    MainActor.assumeIsolated {
        NavigationStack {
            PlayerView(
                store: Store(initialState: PlayerFeature.State(bookSummary: BookSummary.mock)) {
                    PlayerFeature()
                        ._printChanges()
                }
            )
        }
    }
}
