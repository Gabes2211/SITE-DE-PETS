import AppIntents

struct LigarLampadasIntent: AppIntent {
    static var title: LocalizedStringResource = "Ligar lâmpadas"
    static var description = IntentDescription("Liga as lâmpadas escolhidas em Ajustes no app Casa.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let n = try await AppStore.shared.executarAtalho(ligar: true)
        return .result(dialog: "\(n) lâmpada(s) ligada(s).")
    }
}

struct DesligarLampadasIntent: AppIntent {
    static var title: LocalizedStringResource = "Desligar lâmpadas"
    static var description = IntentDescription("Desliga as lâmpadas escolhidas em Ajustes no app Casa.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let n = try await AppStore.shared.executarAtalho(ligar: false)
        return .result(dialog: "\(n) lâmpada(s) desligada(s).")
    }
}

struct CasaAtalhos: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LigarLampadasIntent(),
                    phrases: ["Ligar lâmpadas no \(.applicationName)", "Acender luzes no \(.applicationName)"],
                    shortTitle: "Ligar lâmpadas", systemImageName: "lightbulb.fill")
        AppShortcut(intent: DesligarLampadasIntent(),
                    phrases: ["Desligar lâmpadas no \(.applicationName)", "Apagar luzes no \(.applicationName)"],
                    shortTitle: "Desligar lâmpadas", systemImageName: "lightbulb.slash")
    }
}
