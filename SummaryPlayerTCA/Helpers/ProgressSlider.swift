import SwiftUI

struct ProgressSlider: View {
    @Binding var value: Int
    let hintKey: String
    @State private var sliderValue: Double = 0.0

    var body: some View {
        Slider(value: $sliderValue) {
            if !$0 {
                sliderChanged(to: sliderValue)
            }
        }
    }

    private func sliderChanged(to newValue: Double) {
        sliderValue = newValue.rounded()
        let roundedValue = Int(sliderValue)
        if roundedValue == value {
            return
        }

        value = roundedValue
    }
}
