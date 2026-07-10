import SwiftUI

/// Bottom strip: terminal-style chronological event log (F5).
struct ActivityFeedView: View {
    @EnvironmentObject var state: AppState

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.border)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { state.feedCollapsed.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 10))
                    Text("ACTIVITY")
                        .font(Theme.ui(9.5, weight: .bold))
                        .kerning(0.8)
                    Text("\(state.events.count)")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                    Spacer()
                    Image(systemName: state.feedCollapsed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Theme.surface)

            if !state.feedCollapsed {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(state.events) { event in
                                eventRow(event).id(event.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    .frame(height: 110)
                    .background(Theme.surface)
                    .onChange(of: state.events.count) { _, _ in
                        if let last = state.events.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: event.date))
                .font(Theme.mono(10))
                .foregroundStyle(Theme.textFaint)
            Text("[\(event.targetName)]")
                .font(Theme.mono(10, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text(event.message)
                .font(Theme.mono(10))
                .foregroundStyle(color(for: event.kind))
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func color(for kind: ActivityEvent.Kind) -> Color {
        switch kind {
        case .info: return Theme.textSecondary
        case .success: return Theme.green
        case .warning: return Theme.amber
        case .error: return Theme.red
        }
    }
}
