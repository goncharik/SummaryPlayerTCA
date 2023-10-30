import AVFoundation
import ComposableArchitecture
import Foundation

// MARK: - AudioSessionClient

struct AudioSessionClient {
    var enablePlayback: @Sendable (_ updateActivation: Bool) throws -> Void
    var disablePlayback: @Sendable (_ updateActivation: Bool) throws -> Void
}

extension DependencyValues {
    var audioSession: AudioSessionClient {
        get { self[AudioSessionClient.self] }
        set { self[AudioSessionClient.self] = newValue }
    }
}

// MARK: - AudioSessionClient + DependencyKey

extension AudioSessionClient: DependencyKey {
    static var liveValue: AudioSessionClient = {
        let isPlaybackActive = LockIsolated(false)

        return AudioSessionClient(
            enablePlayback: { updateActivation in
                isPlaybackActive.setValue(true)
                if AVAudioSession.sharedInstance().category != .playAndRecord {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
                }

                if updateActivation, isPlaybackActive.value {
                    try AVAudioSession.sharedInstance().setActive(true)
                }
            },
            disablePlayback: { updateActivation in
                isPlaybackActive.setValue(false)
                if AVAudioSession.sharedInstance().category == .playAndRecord {
                    try AVAudioSession.sharedInstance().setCategory(.record, mode: .default, options: [.allowBluetooth])
                }

                if updateActivation, !isPlaybackActive.value {
                    try AVAudioSession.sharedInstance().setActive(false)
                }
            }
        )
    }()
}
