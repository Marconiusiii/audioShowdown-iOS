import SwiftUI

struct AppSectionHeading: View {
    let title: String
    let theme: GameTheme

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(theme.line)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(theme.table)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isHeader)
    }
}

struct AppTextRow: View {
    let text: String
    let theme: GameTheme
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(theme.line)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: alignment == .center ? .center : .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(theme.background)
            .contentShape(Rectangle())
    }
}

struct AppButtonRow: View {
    let title: String
    let theme: GameTheme
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? theme.background : theme.accent)
        .background(prominent ? theme.accent : theme.background)
        .contentShape(Rectangle())
    }
}

struct AppToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let theme: GameTheme

    var body: some View {
        Toggle(title, isOn: $isOn)
            .font(.body)
            .foregroundStyle(theme.line)
            .tint(theme.accent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(theme.background)
            .contentShape(Rectangle())
    }
}

struct AppAdjustableSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let theme: GameTheme
    var valueChanged: (Double) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 12)
                Text(valueText)
                    .font(.body.monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(theme.line)
            .fixedSize(horizontal: false, vertical: true)

            Slider(value: visualBinding, in: range, step: step)
                .tint(theme.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(theme.background)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(title)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction(adjust)
    }

    private var visualBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                value = newValue
                valueChanged(newValue)
            }
        )
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let delta = direction == .increment ? step : -step
        let newValue = min(max(value + delta, range.lowerBound), range.upperBound)
        guard newValue != value else { return }
        value = newValue
        valueChanged(newValue)
    }
}

struct AppCategoricalSliderRow: View {
    let title: String
    let choices: [String]
    @Binding var selection: Int
    let theme: GameTheme
    var selectionChanged: (Int) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 12)
                Text(currentChoice)
                    .font(.body)
                    .multilineTextAlignment(.trailing)
            }
            .foregroundStyle(theme.line)
            .fixedSize(horizontal: false, vertical: true)

            Slider(value: sliderBinding, in: 0...Double(max(0, choices.count - 1)), step: 1)
                .tint(theme.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(theme.background)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(title)
        .accessibilityLabel(title)
        .accessibilityValue(currentChoice)
        .accessibilityAdjustableAction(adjust)
    }

    private var currentChoice: String {
        choices.indices.contains(selection) ? choices[selection] : ""
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { Double(selection) },
            set: { updateSelection(Int($0.rounded())) }
        )
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        updateSelection(selection + (direction == .increment ? 1 : -1))
    }

    private func updateSelection(_ proposed: Int) {
        let newSelection = min(max(proposed, 0), choices.count - 1)
        guard newSelection != selection else { return }
        selection = newSelection
        selectionChanged(newSelection)
    }
}

struct AppMenuPickerRow<Selection: Hashable, Content: View>: View {
    let title: String
    let valueText: String
    @Binding var selection: Selection
    let theme: GameTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        Picker(selection: $selection) {
            content()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(valueText)
                        .font(.body)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.line)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .pickerStyle(.menu)
        .tint(theme.accent)
        .frame(maxWidth: .infinity)
        .background(theme.background)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
    }
}

struct AppLinkRow: View {
    let title: String
    let destination: URL
    let theme: GameTheme

    var body: some View {
        Link(destination: destination) {
            Text(title)
                .font(.body.weight(.semibold))
                .underline()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .foregroundStyle(theme.accent)
        .background(theme.background)
        .contentShape(Rectangle())
    }
}
