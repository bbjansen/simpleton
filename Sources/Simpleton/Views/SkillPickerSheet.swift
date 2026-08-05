import SimpletonCore
// Sources/Simpleton/Views/SkillPickerSheet.swift
import SwiftUI

struct SkillPickerSheet: View {
    let skillStore: SkillStore
    let onSelect: (Skill) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""

    private var filtered: [Skill] {
        guard !searchText.isEmpty else { return skillStore.allSkills }
        let q = searchText.lowercased()
        return skillStore.allSkills.filter {
            $0.name.lowercased().contains(q) || $0.slug.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.system(size: 11))
                TextField("Search skills…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(10)
            .background(DT.base)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    section("Built-in", skills: filtered.filter(\.builtIn))
                    section("Your Skills", skills: filtered.filter { !$0.builtIn })
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 300, height: 380)
        .background(DT.surface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DT.border, lineWidth: 1))
    }

    @ViewBuilder
    private func section(_ title: String, skills: [Skill]) -> some View {
        if !skills.isEmpty {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(skills) { skill in
                Button(action: {
                    onSelect(skill); onDismiss()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: skill.icon)
                            .font(.system(size: 13))
                            .foregroundColor(.purple)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.name).font(.system(size: 12)).foregroundColor(.primary)
                            Text(skill.description).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("/\(skill.slug)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color.purple.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
