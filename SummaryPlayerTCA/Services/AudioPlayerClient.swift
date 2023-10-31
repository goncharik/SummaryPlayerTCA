import Foundation
import ComposableArchitecture

struct AudioPlayerClient {
    var play: @Sendable (PlaybackPosition, URL, Float) -> AsyncStream<PlaybackState>
    var pause: @Sendable () async -> Void
    var stop: @Sendable () async -> Void
    var seekProgress: @Sendable (Double) async -> Void
    var speed: @Sendable (Float) async -> Void
}

extension AudioPlayerClient: DependencyKey {
    class Context {
        var audioPlayer: AudioPlayer?
        var continuation: AsyncStream<PlaybackState>.Continuation?

        init() {}
    }

    static let liveValue: AudioPlayerClient = {
        let context = Context()

        return AudioPlayerClient(
            play: { playbackPosition, url, speed in
                @Dependency(\.audioSession) var audioSession: AudioSessionClient

                let stream = AsyncStream<PlaybackState> { continuation in
                    do {
                        context.continuation = continuation
                        context.audioPlayer = try AudioPlayer(
                            url: url,
                            didFinishPlaying: { successful in
                                try? audioSession.disablePlayback(true)
                                continuation.yield(.finish(successful: successful))
                                continuation.finish()
                            },
                            decodeErrorDidOccur: { error in
                                try? audioSession.disablePlayback(true)
                                continuation.yield(.error(error?.localizedDescription))
                                continuation.finish()
                            }
                        )

                        try audioSession.enablePlayback(true)
                        context.audioPlayer?.player.enableRate = true
                        context.audioPlayer?.player.prepareToPlay()
                        context.audioPlayer?.player.currentTime = playbackPosition.currentTime
                        context.audioPlayer?.player.rate = speed
                        context.audioPlayer?.player.play()
                        let timerTask = Task {
                            let clock = ContinuousClock()
                            for await _ in clock.timer(interval: .milliseconds(100)) {
                                guard context.audioPlayer?.player.isPlaying == true else { continue }

                                let position = PlaybackPosition(
                                    currentTime: context.audioPlayer?.player.currentTime ?? 0,
                                    duration: context.audioPlayer?.player.duration ?? 0
                                )
                                continuation.yield(.playing(position))
                            }
                        }
                        continuation.onTermination = { _ in
                            context.audioPlayer?.player.stop()
                            timerTask.cancel()
                        }
                    } catch {
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish()
                    }
                }
                return stream
            },
            pause: {
                context.audioPlayer?.player.pause()
                context.continuation?.yield(.pause(PlaybackPosition(
                    currentTime: context.audioPlayer?.player.currentTime ?? 0,
                    duration: context.audioPlayer?.player.duration ?? 0
                )))
            },
            stop: {
                context.audioPlayer?.player.stop()
                context.continuation?.yield(.stop)
            },
            seekProgress: { progress in
                if let player = context.audioPlayer?.player {
                    let progress = min(1, max(0, progress))
                    let time = player.duration * progress
                    if progress == 1 {
                        player.stop()
                        context.continuation?.yield(.playing(PlaybackPosition(
                            currentTime: context.audioPlayer?.player.duration ?? 0,
                            duration: context.audioPlayer?.player.duration ?? 0
                        )))
                    } else {
                        await MainActor.run {
                            if player.isPlaying {
                                player.pause()
                                player.currentTime = time
                                player.play()
                            } else {
                                player.currentTime = time
                            }
                        }
                        context.continuation?.yield(.playing(PlaybackPosition(
                            currentTime: context.audioPlayer?.player.currentTime ?? 0,
                            duration: context.audioPlayer?.player.duration ?? 0
                        )))
                    }
                }
            },
            speed: { speed in
                if context.audioPlayer?.player.isPlaying == true {
                    context.audioPlayer?.player.pause()
                    context.audioPlayer?.player.rate = speed
                    context.audioPlayer?.player.play()
                }
            }
        )
    }()
}

extension DependencyValues {
    var audioPlayer: AudioPlayerClient {
        get { self[AudioPlayerClient.self] }
        set { self[AudioPlayerClient.self] = newValue }
    }
}

// MARK: - Helper models

// MARK: - PlaybackPosition

struct PlaybackPosition: Equatable {
    var currentTime: TimeInterval
    var duration: TimeInterval

    var progress: Double { currentTime / duration }
}

// MARK: - PlaybackState

enum PlaybackState: Equatable {
    case playing(PlaybackPosition)
    case pause(PlaybackPosition)
    case stop
    case error(String?)
    case finish(successful: Bool)
}
