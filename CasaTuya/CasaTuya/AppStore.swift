import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var credentials: TuyaCredentials?
    @Published private(set) var devices: [TuyaDevice] = []
    @Published private(set) var rotinas: [Rotina] = []
    /// Lâmpadas que os Atalhos do iOS ("Ligar/Desligar lâmpadas") controlam.
    @Published var atalhoDeviceIds: Set<String> = [] { didSet { salvarLocal() } }
    @Published var carregando = false
    @Published var erro: String?

    let client: TuyaClient
    private let defaults = UserDefaults.standard

    private init() {
        let creds = Keychain.load(key: "credentials").flatMap { try? JSONDecoder().decode(TuyaCredentials.self, from: $0) }
        credentials = creds
        client = TuyaClient(credentials: creds)
        if let d = defaults.data(forKey: "devices"), let v = try? JSONDecoder().decode([TuyaDevice].self, from: d) { devices = v }
        if let d = defaults.data(forKey: "rotinas"), let v = try? JSONDecoder().decode([Rotina].self, from: d) { rotinas = v }
        atalhoDeviceIds = Set(defaults.stringArray(forKey: "atalhoDeviceIds") ?? [])
    }

    var configurado: Bool { credentials != nil }

    func device(id: String) -> TuyaDevice? { devices.first { $0.id == id } }

    // MARK: - Credenciais

    func salvarCredenciais(_ c: TuyaCredentials) async {
        if let data = try? JSONEncoder().encode(c) { Keychain.save(data, key: "credentials") }
        credentials = c
        await client.setCredentials(c)
        await carregarDispositivos()
    }

    func apagarCredenciais() async {
        Keychain.delete(key: "credentials")
        credentials = nil
        await client.setCredentials(nil)
    }

    // MARK: - Dispositivos

    func carregarDispositivos() async {
        carregando = true
        defer { carregando = false }
        do {
            devices = try await client.listarDispositivos().sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            if atalhoDeviceIds.isEmpty { atalhoDeviceIds = Set(devices.map(\.id)) }
            erro = nil
            salvarLocal()
        } catch {
            erro = error.localizedDescription
        }
    }

    func alternar(_ device: TuyaDevice, ligar: Bool) async {
        do {
            try await client.enviarComando(deviceId: device.id, code: device.switchCode, value: .bool(ligar))
            atualizarEstado(deviceId: device.id, ligado: ligar)
        } catch {
            erro = error.localizedDescription
        }
    }

    /// Usado pelos Atalhos do iOS. Retorna quantas lâmpadas responderam.
    func executarAtalho(ligar: Bool) async throws -> Int {
        let alvos = devices.filter { atalhoDeviceIds.contains($0.id) }
        guard !alvos.isEmpty else { return 0 }
        var ok = 0
        var ultimoErro: Error?
        for d in alvos {
            do {
                try await client.enviarComando(deviceId: d.id, code: d.switchCode, value: .bool(ligar))
                atualizarEstado(deviceId: d.id, ligado: ligar)
                ok += 1
            } catch {
                ultimoErro = error
            }
        }
        if ok == 0, let ultimoErro { throw ultimoErro }
        return ok
    }

    private func atualizarEstado(deviceId: String, ligado: Bool) {
        guard let i = devices.firstIndex(where: { $0.id == deviceId }) else { return }
        let code = devices[i].switchCode
        var status = devices[i].status ?? []
        if let j = status.firstIndex(where: { $0.code == code }) {
            status[j].value = .bool(ligado)
        } else {
            status.append(DeviceStatus(code: code, value: .bool(ligado)))
        }
        devices[i].status = status
    }

    // MARK: - Rotinas (timers na nuvem da Tuya)

    func criarRotina(_ rotina: Rotina) async -> Bool {
        carregando = true
        defer { carregando = false }
        do {
            for id in rotina.deviceIds {
                let code = device(id: id)?.switchCode ?? "switch_led"
                if let h = rotina.ligar {
                    try await client.criarTimer(deviceId: id, alias: "\(rotina.tag)-ligar", hora: h.texto,
                                                loops: rotina.loops, code: code, value: .bool(true))
                }
                if let h = rotina.desligar {
                    try await client.criarTimer(deviceId: id, alias: "\(rotina.tag)-desligar", hora: h.texto,
                                                loops: rotina.loops, code: code, value: .bool(false))
                }
            }
            rotinas.append(rotina)
            salvarLocal()
            erro = nil
            return true
        } catch {
            // Desfaz o que já tinha sido criado para não deixar timers soltos.
            await apagarTimersNaNuvem(da: rotina)
            erro = error.localizedDescription
            return false
        }
    }

    func apagarRotina(_ rotina: Rotina) async {
        carregando = true
        defer { carregando = false }
        await apagarTimersNaNuvem(da: rotina)
        rotinas.removeAll { $0.id == rotina.id }
        salvarLocal()
    }

    private func apagarTimersNaNuvem(da rotina: Rotina) async {
        for id in rotina.deviceIds {
            do {
                let ids = try await client.listarTimers(deviceId: id)
                    .filter { $0.alias.hasPrefix(rotina.tag) }
                    .map(\.id)
                try await client.apagarTimers(deviceId: id, ids: ids)
            } catch {
                erro = error.localizedDescription
            }
        }
    }

    func timersNaNuvem(deviceId: String) async throws -> [TimerNuvem] {
        try await client.listarTimers(deviceId: deviceId)
    }

    // MARK: - Persistência local

    private func salvarLocal() {
        if let d = try? JSONEncoder().encode(devices) { defaults.set(d, forKey: "devices") }
        if let d = try? JSONEncoder().encode(rotinas) { defaults.set(d, forKey: "rotinas") }
        defaults.set(Array(atalhoDeviceIds), forKey: "atalhoDeviceIds")
    }
}
