import SwiftUI

/// The app icon, drawn with the same ring-gauge language as the UI so the brand
/// reads consistently. Rendered offscreen to a 1024px PNG via `--render-icon`,
/// then packed into an .icns by scripts/make-icon.sh.
struct IconView: View {
    var body: some View {
        ZStack {
            Color.clear
            ZStack {
                // Geist-black squircle.
                RoundedRectangle(cornerRadius: 184, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x1C1C28), Color(hex: 0x070709)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 184, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 2)
                    )

                // Soft blue bloom — the "lumen".
                Circle()
                    .fill(Color(hex: 0x0070F3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 130)
                    .opacity(0.55)

                // Signature ring gauge.
                Circle()
                    .trim(from: 0, to: 0.78)
                    .stroke(
                        AngularGradient(
                            colors: [Color(hex: 0x0070F3), Color(hex: 0x3D9DFF), Color(hex: 0x9FD8FF)],
                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 70, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 470, height: 470)

                // Center light point.
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), Color(hex: 0x9FD8FF).opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 70))
                    .frame(width: 150, height: 150)
            }
            .frame(width: 824, height: 824)
        }
        .frame(width: 1024, height: 1024)
    }
}
