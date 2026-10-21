import SwiftUI
import SonosKit

struct GroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @FocusState private var doneFocused: Bool
    @State private var chosen: Set<String> = []
    @State private var ignoreSyncUntil = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where is it playing?")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(doneFocused ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .focusEffectDisabled()
                    .focused($doneFocused)
                    .accessibilityLabel("Done")
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 6)

            HStack {
                Text(model.selected?.name ?? "This room")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Current room, \(model.selected?.name ?? "This room")")
                Spacer()
                Button("Select all") { selectAll() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(rooms.isEmpty || chosen.count == rooms.count)
                    .accessibilityLabel("Select all rooms")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            if let group = model.selected, chosen.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group volume")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: group.groupMuted ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        ThinSlider(
                            value: Binding(
                                get: { model.groupVolume(group) },
                                set: { model.setGroupVolume($0, group: group) }
                            ),
                            onEditingChanged: { editing in
                                if !editing { model.endGroupVolume(group) }
                            },
                            accessibilityTitle: "Group volume"
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rooms) { member in
                        roomRow(member)
                        if member.id != rooms.last?.id {
                            Divider().padding(.leading, 24).opacity(0.45)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(width: 420, height: 560)
        .background(Palette.background(scheme))
        .onAppear { syncFromGroup() }
        .onChange(of: selectedMemberKey) { _, _ in
            guard Date() > ignoreSyncUntil else { return }
            syncFromGroup()
        }
    }

    private var selectedMemberKey: String {
        model.selected?.members.map(\.uuid).sorted().joined(separator: ",") ?? ""
    }

    private var rooms: [MemberSnapshot] {
        var seen = Set<String>()
        var byHost: [String: Int] = [:]
        var list: [MemberSnapshot] = []
        for group in model.snapshot.groups {
            for member in group.members {
                guard seen.insert(member.uuid).inserted else { continue }
                if !member.host.isEmpty, let index = byHost[member.host] {
                    if RoomName.isPlaceholder(list[index].name), !RoomName.isPlaceholder(member.name) {
                        list[index] = member
                    }
                    continue
                }
                if !member.host.isEmpty {
                    byHost[member.host] = list.count
                }
                list.append(member)
            }
        }
        return list
    }

    private func roomRow(_ member: MemberSnapshot) -> some View {
        let on = chosen.contains(member.uuid)
        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { chosen.contains(member.uuid) },
                set: { setIncluded(member, $0) }
            )) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .lineLimit(1)
                    if let battery = member.battery {
                        BatteryReadout(battery: battery)
                    }
                }
            }
            .toggleStyle(RoomCheckToggleStyle())
            .accessibilityLabel(member.battery.map { "\(member.name), \($0.accessibilityLabel)" } ?? member.name)
            .accessibilityValue(on ? "Playing here" : "Not playing here")
            .accessibilityHint("Include or remove this room")
            if on {
                HStack(spacing: 8) {
                    Image(systemName: member.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    ThinSlider(
                        value: Binding(
                            get: { model.memberVolume(member) },
                            set: { model.setMemberVolume($0, member: member) }
                        ),
                        onEditingChanged: { editing in
                            if !editing { model.endMemberVolume(member) }
                        },
                        accessibilityTitle: "\(member.name) volume"
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func setIncluded(_ member: MemberSnapshot, _ on: Bool) {
        if on {
            chosen.insert(member.uuid)
        } else {
            guard chosen.count > 1 else { return }
            chosen.remove(member.uuid)
        }
        holdSync()
        model.setMembership(Array(chosen))
    }

    private func selectAll() {
        chosen = Set(rooms.map(\.uuid))
        guard !chosen.isEmpty else { return }
        holdSync()
        model.setMembership(Array(chosen))
    }

    private func syncFromGroup() {
        chosen = Set(model.selected?.members.map(\.uuid) ?? [])
    }

    private func holdSync() {
        ignoreSyncUntil = Date().addingTimeInterval(1.6)
    }
}

/// Checkmark row that VoiceOver and the keyboard treat as a toggle.
private struct RoomCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .font(.system(size: 17, weight: configuration.isOn ? .semibold : .regular))
                Spacer(minLength: 8)
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(configuration.isOn ? Color.primary : Color.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
