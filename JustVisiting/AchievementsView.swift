import SwiftUI

struct AchievementsView: View {
    @Environment(AchievementsManager.self) private var am
    @Environment(PlacesManager.self) private var pm

    private var unlockedCount: Int {
        AchievementDefinition.all.filter { am.isUnlocked($0) }.count
    }
    private var total: Int { AchievementDefinition.all.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    SummaryCard(unlocked: unlockedCount, total: total)

                    ForEach(AchievementCategory.allCases, id: \.self) { category in
                        CategorySection(
                            category: category,
                            definitions: AchievementDefinition.all.filter { $0.category == category },
                            am: am
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Achievements")
        }
    }
}

// MARK: - Summary header

private struct SummaryCard: View {
    let unlocked: Int
    let total: Int
    private var fraction: Double { total > 0 ? Double(unlocked) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(unlocked) of \(total) unlocked")
                    .font(.headline)
                ProgressView(value: fraction)
                    .tint(.yellow)
                Text(String(format: "%.0f%% complete", fraction * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Category section

private struct CategorySection: View {
    let category: AchievementCategory
    let definitions: [AchievementDefinition]
    let am: AchievementsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(category.rawValue, systemImage: category.icon)
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(definitions, id: \.id) { def in
                    AchievementRow(def: def, am: am)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Single achievement row

private struct AchievementRow: View {
    let def: AchievementDefinition
    let am: AchievementsManager

    private var unlocked: Bool { am.isUnlocked(def) }
    private var unlockedDate: Date? { am.unlockedAt(def) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: def.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(unlocked ? def.color : .secondary)
                .frame(width: 44, height: 44)
                .background(
                    (unlocked ? def.color : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(def.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(unlocked ? .primary : .secondary)
                Text(def.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = unlockedDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if unlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .opacity(unlocked ? 1 : 0.65)
    }
}
