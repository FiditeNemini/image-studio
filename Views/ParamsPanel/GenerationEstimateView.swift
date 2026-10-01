import SwiftUI

/// Compact info strip below the dimension picker: learned-time estimate on the
/// left, megapixel count of the current width × height on the right. The estimate
/// stays hidden until there is comparable history for the current
/// model/quantize/size, and appends "(rough)" when the requested pixel count is
/// outside the sampled range (extrapolated); the megapixel readout is always shown.
///
/// With `onSetMegapixels` set (the aspect ratio is locked), the readout becomes an
/// editable field: typing a megapixel count resizes to that area at the locked ratio.
struct GenerationEstimateView: View {
    let estimate: TimingStore.Estimate?
    let width: Int
    let height: Int
    var onSetMegapixels: ((Double) -> Void)?

    // Buffered like DimensionSliderRow: committed on Return or focus-out, so the
    // resize never fires mid-keystroke.
    @State private var megapixelInput: String = ""
    @FocusState private var megapixelFocused: Bool

    private var megapixels: Double {
        Double(width * height) / 1_000_000
    }

    private var megapixelNumber: String {
        String(format: megapixels < 1 ? "%.2f" : "%.1f", megapixels)
    }

    private var megapixelText: String {
        "\(megapixelNumber) MP"
    }

    var body: some View {
        Divider()
        HStack(spacing: 4) {
            if let estimate {
                Image(systemName: "clock")
                Text("Est. ~\(RunnerSupport.formatDuration(estimate.seconds))\(estimate.isApproximate ? " (rough)" : "")")
                    .help(estimate.isApproximate
                        ? "Rough estimate — extrapolated from a different image size."
                        : "Estimated from previous runs at a similar pixel count.")
            }
            Spacer(minLength: 8)
            if onSetMegapixels != nil {
                megapixelField
            } else {
                Text(megapixelText)
                    .monospacedDigit()
                    .help("\(width) × \(height) = \(megapixelText) total pixels.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var megapixelField: some View {
        HStack(spacing: 3) {
            TextField("", text: $megapixelInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption2, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .focused($megapixelFocused)
                .onSubmit(commitMegapixels)
                .onChange(of: megapixelFocused) { _, isFocused in
                    if !isFocused {
                        commitMegapixels()
                    }
                }
                // Unconditional: Enter keeps focus, and the resized width × height only arrives after commit returns.
                .onChange(of: megapixelNumber) { _, new in megapixelInput = new }
                .onAppear { megapixelInput = megapixelNumber }
                .accessibilityLabel("Megapixels")
                .accessibilityHint("Type a total size in megapixels; width and height follow at the locked aspect ratio")
            Text("MP")
        }
        .help("\(width) × \(height). Type a megapixel count to resize at the locked aspect ratio.")
    }

    /// Unparseable or non-positive input reverts to the live value. An unedited field is a no-op, so blurring
    /// it does not snap a slider-set size (2.04 MP shown as "2.0") to the rounded figure.
    private func commitMegapixels() {
        guard megapixelInput != megapixelNumber else { return }
        if let value = Double(megapixelInput.replacingOccurrences(of: ",", with: ".")), value > 0 {
            onSetMegapixels?(value)
        }
        megapixelInput = megapixelNumber
    }
}
