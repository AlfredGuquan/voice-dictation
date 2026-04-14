import SwiftUI

/// Dark pill-shaped toast body. Matches v03-brief § 02 Toast.
struct ToastView: View {
    let kind: ToastManager.Kind
    let message: String
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 12, height: 12)

            Text(message)
                .font(.system(size: 11.5))
                .foregroundColor(Color(red: 1.0, green: 0.992, blue: 0.980).opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if kind == .error {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.992, blue: 0.980).opacity(0.6))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color(red: 40/255, green: 30/255, blue: 22/255).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 2)
        )
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }

    private var iconName: String {
        switch kind {
        case .error: return "exclamationmark.circle.fill"
        case .info:  return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch kind {
        case .error: return Color(red: 0xF4/255, green: 0xA8/255, blue: 0x8B/255)
        case .info:  return Color(red: 0xF0/255, green: 0xC7/255, blue: 0x8E/255)
        }
    }
}
