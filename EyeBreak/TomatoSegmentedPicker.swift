import SwiftUI

/// 设置共用的番茄分段控件，提示音、外观和语言保持同样的尺寸与选中反馈。
struct TomatoSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    onSelect(option)
                } label: {
                    Text(verbatim: title(option))
                        .font(Theme.font(12, .semibold))
                        .lineLimit(1)
                        .foregroundStyle(selected ? .white : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.smallControlSize - Theme.Spacing.segmented * 2)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(selected ? Theme.tomatoFill : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Theme.Spacing.segmented)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.segmented, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.segmented, style: .continuous)
                .strokeBorder(Theme.creamDeep, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}
