import SwiftUI

/// Scale selector. Hindustani name first, Carnatic and Western names beneath,
/// so every player finds the name they know without a tradition setting.
struct ScaleMenuView: View {
    @Binding var scale: Scale

    var body: some View {
        Menu {
            Picker("Scale", selection: $scale) {
                ForEach(Scale.all) { s in
                    Text(s.displaySubtitle.map { "\(s.displayTitle) \u{00B7} \($0)" } ?? s.displayTitle)
                        .tag(s)
                }
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scale.displayTitle)
                        .font(Theme.serif(17, weight: .medium))
                        .foregroundColor(Theme.ivory)
                    Text(scale.displaySubtitle ?? " ")
                        .font(Theme.serif(12))
                        .foregroundColor(Theme.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.brass)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .accessibilityLabel("Scale")
        .accessibilityValue(scale.allNames.joined(separator: ", "))
    }
}
