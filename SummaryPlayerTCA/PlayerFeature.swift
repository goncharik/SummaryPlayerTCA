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
}

extension BookSummary {
    static var mock: Self = BookSummary(
        id: UUID(0),
        title: "title",
        imageName: "book_cover",
        chapters: [
            .init(title: "Chapter 1", audioFileName: "one", duration: 60),
            .init(title: "Chapter 2", audioFileName: "two", duration: 70),
        ]
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
                case .x05: return "0.5x"
                case .x075: return "0.75x"
                case .x1: return "1x"
                case .x15: return "1.5x"
                case .x2: return "2x"
                }
            }

            var speedMultiplier: Double {
                switch self {
                case .x05: return 0.5
                case .x075: return 0.75
                case .x1: return 1
                case .x15: return 1.5
                case .x2: return 2
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
        var chapterProgress: Double = 0
        var playbackSpeed: PlaybackSpeed = .x1
    }

    enum Action: Equatable {
//        case audioPlayerClient(TaskResult<Bool>)

        case playButtonTapped
        case pauseButtonTapped

        case fastForwardButtonTapped
        case rewindButtonTapped

        case progressSliderMoved(Double)

        case nextChapterButtonTapped
        case previousChapterButtonTapped

        case speedButtonTapped

        case timerUpdated(TimeInterval)
        case updateChapterIfNeeded
    }

//    @Dependency(\.audioPlayer) var audioPlayer
    @Dependency(\.continuousClock) var clock
    private enum CancelID { case play }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .playButtonTapped:
                state.isPlaying = true
//                var start: TimeInterval = state.chapterProgress * (state.currentChapter?.duration ?? 0)

                return .run { /* [url = state.url] */ send in
//                    async let playAudio: Void = send(
//                        .audioPlayerClient(TaskResult { try await self.audioPlayer.play(url) })
//                    )

                    let tickTime = 0.5

                    for await _ in clock.timer(interval: .milliseconds(500)) {
                        await send(.timerUpdated(tickTime))
                    }

//                    await playAudio
                }
                .cancellable(id: CancelID.play, cancelInFlight: true)

            case .pauseButtonTapped:
                state.isPlaying = false
                return .cancel(id: CancelID.play)
            case .fastForwardButtonTapped:
                // TODO: self.audioPlayer.update
                return .send(.timerUpdated(10))
            case .rewindButtonTapped:
                // TODO: self.audioPlayer.update
                return .send(.timerUpdated(-5))
            case let .progressSliderMoved(progress):
                state.chapterProgress = progress
                // TODO: self.audioPlayer.update
                return .none
            case .nextChapterButtonTapped:
                state.chapterProgress = 1
                return .send(.updateChapterIfNeeded)
            case .previousChapterButtonTapped:
                guard state.currentChapterIndex > 0 else { return .none }
                state.chapterProgress = 0
                state.currentChapterIndex -= 1
                // TODO: self.audioPlayer.update
                return .none
            case .speedButtonTapped:
                state.playbackSpeed = state.playbackSpeed == State.PlaybackSpeed.allCases.last
                    ? State.PlaybackSpeed.allCases.first!
                    : State.PlaybackSpeed.allCases.first { $0.speedMultiplier > state.playbackSpeed.speedMultiplier }!

                // TODO: self.audioPlayer.update

                return .none
            case let .timerUpdated(tickTime):
                guard state.isPlaying, let currentChapter = state.currentChapter else { return .none }
                let time = max(0, state.chapterProgress * currentChapter.duration + tickTime)
                state.chapterProgress = min(1, time / currentChapter.duration)
                return .send(.updateChapterIfNeeded)
            case .updateChapterIfNeeded:
                if state.chapterProgress == 1 {
                    state.currentChapterIndex = (state.currentChapterIndex + 1) % state.bookSummary.chapters.count
                    if state.currentChapterIndex == 0 {
                        // stoping playback so summary is fully listened to
                        state.isPlaying = false
                    }
                    state.chapterProgress = 0
                    // TODO: self.audioPlayer.update
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
            let duration = viewStore.state.currentChapter?.duration
            let currentTime: TimeInterval = {
                let duration = duration ?? 0
                if duration > 0 {
                    return min(duration, viewStore.state.chapterProgress * duration)
                } else {
                    return 0
                }
            }()
            let timeLeft = (duration ?? 0) - currentTime


            VStack(alignment: .center) {
                // MARK: - Book image
                GeometryReader {
                    let size = $0.size

                    VStack(alignment: .center){
                        Image(viewStore.bookSummary.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size.width / 2, alignment: .center)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()

                // MARK: - Chapter number

                Text("KEY POINT \(viewStore.currentChapterIndex + 1) OF \(viewStore.bookSummary.chapters.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(8)

                // MARK: - Chapter title

                Text(viewStore.currentChapter?.title ?? "")
                    .font(.body)
                    .padding(8)

                // MARK: - Playback progress

                HStack(spacing: 12) {
                    dateComponentsFormatter.string(from: currentTime).map {
                        Text($0)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(Color(.systemGray))
                    }

                    Slider(
                        value: viewStore.binding(
                            get: { $0.chapterProgress },
                            send: PlayerFeature.Action.progressSliderMoved
                        )
                    )
                    .disabled(duration == nil)

                    dateComponentsFormatter.string(from: timeLeft).map {
                        Text($0)
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(Color(.systemGray))
                    }
                }
                .buttonStyle(.borderless)
                .padding()

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


                Spacer()
                    .frame(maxHeight: .infinity)

                // TODO: add some button for ui
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MainActor.assumeIsolated {
        NavigationStack {
            PlayerView(
                store: Store(initialState: PlayerFeature.State(bookSummary: BookSummary.mock, chapterProgress: 0.3)) {
                    PlayerFeature()
                        ._printChanges()
                }
            )
        }
    }
}
