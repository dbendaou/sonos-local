import SwiftUI
import SonosKit

struct GroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var chosen: Set<String> = []
    @State private var ignoreSyncUntil = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where is it playing?")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 6)

            HStack {
                Text(model.selected?.name ?? "This room")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select all") { selectAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(rooms.isEmpty || chosen.count == rooms.count)
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
        var list: [MemberSnapshot] = []
        for group in model.snapshot.groups {
            for member in group.members where seen.insert(member.uuid).inserted {
                list.append(member)
            }
        }
        return list
    }

    private func roomRow(_ member: MemberSnapshot) -> some View {
        let on = chosen.contains(member.uuid)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                toggle(member)
            } label: {
                HStack(spacing: 12) {
                    Text(member.name)
                        .font(.system(size: 17, weight: on ? .semibold : .regular))
                    Spacer(minLength: 8)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(on ? Color.primary : Color.secondary.opacity(0.7))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(member.name)
            .accessibilityAddTraits(on ? .isSelected : [])
            if on {
                HStack(spacing: 8) {
                    Image(systemName: member.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

    private func toggle(_ member: MemberSnapshot) {
        if chosen.contains(member.uuid) {
            guard chosen.count > 1 else { return }
            chosen.remove(member.uuid)
        } else {
            chosen.insert(member.uuid)
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
