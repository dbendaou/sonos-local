import SwiftUI
import SonosKit

struct GroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Group")
                        .font(.system(size: 22, weight: .semibold))
                    Text(model.selected?.name ?? "Room")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(rooms) { member in
                        roomRow(member)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 440, height: 520)
        .background(Palette.background(scheme))
        .onAppear {
            chosen = Set(model.selected?.members.map(\.uuid) ?? [])
        }
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
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle(member)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 15, weight: .semibold))
                        if !member.modelName.isEmpty {
                            Text(member.modelName)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
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
                .padding(.leading, 30)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card(scheme)))
    }

    private func toggle(_ member: MemberSnapshot) {
        if chosen.contains(member.uuid) {
            guard chosen.count > 1 else { return }
            chosen.remove(member.uuid)
        } else {
            chosen.insert(member.uuid)
        }
        model.setMembership(Array(chosen))
    }
}
