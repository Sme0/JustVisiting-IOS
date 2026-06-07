import SwiftUI

@Observable
final class AchievementsManager {

    private(set) var unlockedIds: [String: Date] = [:]
    private(set) var recentlyUnlocked: AchievementDefinition?

    private let achievementsURL: URL
    private var bannerWorkItem: DispatchWorkItem?
    private var bannerQueue: [AchievementDefinition] = []

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        achievementsURL = docs.appendingPathComponent("achievements.json")
        load()
    }

    func isUnlocked(_ def: AchievementDefinition) -> Bool {
        unlockedIds[def.id] != nil
    }

    func unlockedAt(_ def: AchievementDefinition) -> Date? {
        unlockedIds[def.id]
    }

    func evaluate(against pm: PlacesManager) {
        var newlyUnlocked: [AchievementDefinition] = []
        for def in AchievementDefinition.all where unlockedIds[def.id] == nil {
            if def.check(pm) {
                unlockedIds[def.id] = Date()
                newlyUnlocked.append(def)
            }
        }
        guard !newlyUnlocked.isEmpty else { return }
        save()
        bannerQueue.append(contentsOf: newlyUnlocked)
        if recentlyUnlocked == nil { showNextBanner() }
    }

    func reset() {
        unlockedIds = [:]
        bannerWorkItem?.cancel()
        bannerWorkItem = nil
        bannerQueue = []
        recentlyUnlocked = nil
        try? FileManager.default.removeItem(at: achievementsURL)
    }

    func dismissBanner() {
        bannerWorkItem?.cancel()
        recentlyUnlocked = nil
        schedule(after: 0.4) { [weak self] in self?.showNextBanner() }
    }

    private func showNextBanner() {
        guard !bannerQueue.isEmpty else { return }
        let def = bannerQueue.removeFirst()
        recentlyUnlocked = def
        schedule(after: 4.0) { [weak self] in
            guard let self else { return }
            self.recentlyUnlocked = nil
            if !self.bannerQueue.isEmpty {
                self.schedule(after: 0.4) { [weak self] in self?.showNextBanner() }
            }
        }
    }

    private func schedule(after delay: TimeInterval, work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        bannerWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func load() {
        guard let data = try? Data(contentsOf: achievementsURL),
              let records = try? JSONDecoder().decode([AchievementRecord].self, from: data) else { return }
        unlockedIds = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.unlockedAt) })
    }

    private func save() {
        let records = unlockedIds.map { AchievementRecord(id: $0.key, unlockedAt: $0.value) }
        let url = achievementsURL
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(records) {
                try? encoded.write(to: url)
            }
        }
    }
}
