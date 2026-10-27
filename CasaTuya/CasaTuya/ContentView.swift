import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var aba = 0

    var body: some View {
        TabView(selection: $aba) {
            DispositivosView()
                .tabItem { Label("Lâmpadas", systemImage: "lightbulb.fill") }
                .tag(0)
            RotinasView()
                .tabItem { Label("Rotinas", systemImage: "clock.fill") }
                .tag(1)
            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .onAppear { if !store.configurado { aba = 2 } }
        .alert("Ops", isPresented: Binding(get: { store.erro != nil }, set: { if !$0 { store.erro = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.erro ?? "")
        }
    }
}

// MARK: - Lâmpadas

struct DispositivosView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                if store.devices.isEmpty {
                    Text(store.configurado
                         ? "Nenhum dispositivo encontrado. Puxe para atualizar."
                         : "Configure sua conta Tuya na aba Ajustes.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.devices) { device in
                    LinhaDispositivo(device: device)
                }
                if store.devices.count > 1 {
                    Section {
                        Button("Ligar todas") { Task { await todas(true) } }
                        Button("Desligar todas") { Task { await todas(false) } }
                    }
                }
            }
            .navigationTitle("Lâmpadas")
            .refreshable { await store.carregarDispositivos() }
            .overlay { if store.carregando { ProgressView() } }
            .task { if store.configurado && store.devices.isEmpty { await store.carregarDispositivos() } }
        }
    }

    private func todas(_ ligar: Bool) async {
        for d in store.devices { await store.alternar(d, ligar: ligar) }
    }
}

struct LinhaDispositivo: View {
    @EnvironmentObject var store: AppStore
    let device: TuyaDevice

    var body: some View {
        Toggle(isOn: Binding(
            get: { device.isOn ?? false },
            set: { novo in Task { await store.alternar(device, ligar: novo) } }
        )) {
            HStack(spacing: 12) {
                Image(systemName: device.isOn == true ? "lightbulb.fill" : "lightbulb")
                    .foregroundStyle(device.isOn == true ? Color.yellow : Color.secondary)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(device.name)
                    if device.online == false {
                        Text("Offline").font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

// MARK: - Rotinas

struct RotinasView: View {
    @EnvironmentObject var store: AppStore
    @State private var novaRotina = false

    var body: some View {
        NavigationStack {
            List {
                if store.rotinas.isEmpty {
                    Text("Nenhuma rotina. Toque em + para criar, por exemplo: ligar às 18:00 e desligar às 23:00.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.rotinas) { rotina in
                    NavigationLink(value: rotina) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rotina.nome).font(.headline)
                            HStack {
                                if let h = rotina.ligar { Label(h.texto, systemImage: "sunrise.fill") }
                                if let h = rotina.desligar { Label(h.texto, systemImage: "moon.fill") }
                            }
                            .font(.subheadline)
                            Text("\(rotina.resumoDias) · \(rotina.deviceIds.count) lâmpada(s)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    let alvo = idx.map { store.rotinas[$0] }
                    Task { for r in alvo { await store.apagarRotina(r) } }
                }
            }
            .navigationTitle("Rotinas")
            .navigationDestination(for: Rotina.self) { RotinaDetalheView(rotina: $0) }
            .toolbar {
                Button { novaRotina = true } label: { Image(systemName: "plus") }
                    .disabled(store.devices.isEmpty)
            }
            .sheet(isPresented: $novaRotina) { NovaRotinaView() }
            .overlay { if store.carregando { ProgressView() } }
        }
    }
}

struct NovaRotinaView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var nome = "Luzes da noite"
    @State private var usarLigar = true
    @State private var usarDesligar = true
    @State private var ligar = HoraMinuto(hora: 18, minuto: 0)
    @State private var desligar = HoraMinuto(hora: 23, minuto: 0)
    @State private var dias: Set<Int> = Set(1...7)
    @State private var selecionadas: Set<String> = []
    @State private var salvando = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nome") { TextField("Nome", text: $nome) }

                Section("Horários") {
                    Toggle("Ligar", isOn: $usarLigar)
                    if usarLigar {
                        DatePicker("Ligar às", selection: $ligar.date, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Desligar", isOn: $usarDesligar)
                    if usarDesligar {
                        DatePicker("Desligar às", selection: $desligar.date, displayedComponents: .hourAndMinute)
                    }
                }

                Section("Dias") {
                    HStack {
                        ForEach(1...7, id: \.self) { dia in
                            let ativo = dias.contains(dia)
                            Button(String(Calendar.current.veryShortWeekdaySymbols[dia - 1])) {
                                if ativo { dias.remove(dia) } else { dias.insert(dia) }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(ativo ? Color.accentColor : Color.secondary.opacity(0.2), in: Circle())
                            .foregroundStyle(ativo ? Color.white : Color.primary)
                        }
                    }
                    if dias.isEmpty {
                        Text("Sem dias marcados: roda só uma vez, hoje.").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Lâmpadas") {
                    ForEach(store.devices) { d in
                        Button {
                            if selecionadas.contains(d.id) { selecionadas.remove(d.id) } else { selecionadas.insert(d.id) }
                        } label: {
                            HStack {
                                Text(d.name).foregroundStyle(.primary)
                                Spacer()
                                if selecionadas.contains(d.id) { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nova rotina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if salvando {
                        ProgressView()
                    } else {
                        Button("Salvar") { Task { await salvar() } }
                            .disabled(selecionadas.isEmpty || (!usarLigar && !usarDesligar))
                    }
                }
            }
            .onAppear { if selecionadas.isEmpty { selecionadas = Set(store.devices.map(\.id)) } }
        }
    }

    private func salvar() async {
        salvando = true
        let rotina = Rotina(
            nome: nome.isEmpty ? "Rotina" : nome,
            deviceIds: store.devices.map(\.id).filter(selecionadas.contains),
            ligar: usarLigar ? ligar : nil,
            desligar: usarDesligar ? desligar : nil,
            dias: dias)
        let ok = await store.criarRotina(rotina)
        salvando = false
        if ok { dismiss() }
    }
}

struct RotinaDetalheView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let rotina: Rotina
    @State private var timers: [String: [TimerNuvem]] = [:]
    @State private var carregando = true

    var body: some View {
        List {
            Section {
                if let h = rotina.ligar { LabeledContent("Liga às", value: h.texto) }
                if let h = rotina.desligar { LabeledContent("Desliga às", value: h.texto) }
                LabeledContent("Dias", value: rotina.resumoDias)
            }
            Section {
                if carregando { ProgressView() }
                ForEach(rotina.deviceIds, id: \.self) { id in
                    let lista = (timers[id] ?? []).filter { $0.alias.hasPrefix(rotina.tag) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.device(id: id)?.name ?? id).font(.headline)
                        if !carregando && lista.isEmpty {
                            Label("Nenhum timer encontrado na nuvem", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).font(.caption)
                        }
                        ForEach(lista) { t in
                            Label("\(t.descricao) às \(t.time)\(t.ativo ? "" : " (pausado)")",
                                  systemImage: t.ativo ? "checkmark.circle.fill" : "pause.circle")
                                .font(.caption)
                                .foregroundStyle(t.ativo ? Color.green : Color.secondary)
                        }
                    }
                }
            } header: {
                Text("Confirmado na nuvem da Tuya")
            } footer: {
                Text("Esses timers rodam nos servidores da Tuya, então funcionam mesmo com o iPhone desligado.")
            }
            Section {
                Button("Apagar rotina", role: .destructive) {
                    Task {
                        await store.apagarRotina(rotina)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(rotina.nome)
        .task { await carregar() }
        .refreshable { await carregar() }
    }

    private func carregar() async {
        carregando = true
        for id in rotina.deviceIds {
            do {
                timers[id] = try await store.timersNaNuvem(deviceId: id)
            } catch {
                store.erro = error.localizedDescription
            }
        }
        carregando = false
    }
}

// MARK: - Ajustes

struct AjustesView: View {
    @EnvironmentObject var store: AppStore
    @State private var accessId = ""
    @State private var accessSecret = ""
    @State private var region: TuyaRegion = .americaOeste
    @State private var salvando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Access ID / Client ID", text: $accessId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Access Secret / Client Secret", text: $accessSecret)
                    Picker("Data center", selection: $region) {
                        ForEach(TuyaRegion.allCases) { Text($0.nome).tag($0) }
                    }
                    Button {
                        Task {
                            salvando = true
                            await store.salvarCredenciais(TuyaCredentials(
                                accessId: accessId.trimmingCharacters(in: .whitespaces),
                                accessSecret: accessSecret.trimmingCharacters(in: .whitespaces),
                                region: region))
                            salvando = false
                        }
                    } label: {
                        HStack {
                            Text("Salvar e conectar")
                            if salvando { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(accessId.isEmpty || accessSecret.isEmpty)
                } header: {
                    Text("Conta Tuya IoT Platform")
                } footer: {
                    Text("Pegue esses dados em iot.tuya.com → Cloud → seu projeto → Overview. Ficam guardados no Keychain do iPhone.")
                }

                if store.configurado {
                    Section {
                        LabeledContent("Status", value: store.devices.isEmpty ? "Sem dispositivos" : "\(store.devices.count) dispositivo(s)")
                        Button("Desconectar", role: .destructive) { Task { await store.apagarCredenciais() } }
                    }
                }

                if !store.devices.isEmpty {
                    Section {
                        ForEach(store.devices) { d in
                            Toggle(d.name, isOn: Binding(
                                get: { store.atalhoDeviceIds.contains(d.id) },
                                set: { if $0 { store.atalhoDeviceIds.insert(d.id) } else { store.atalhoDeviceIds.remove(d.id) } }))
                        }
                    } header: {
                        Text("Lâmpadas dos Atalhos (Siri)")
                    } footer: {
                        Text("Os atalhos \"Ligar lâmpadas\" e \"Desligar lâmpadas\" controlam estas. Use no app Atalhos → Automação → Horário do Dia como plano B.")
                    }
                }
            }
            .navigationTitle("Ajustes")
            .onAppear {
                if let c = store.credentials {
                    accessId = c.accessId
                    accessSecret = c.accessSecret
                    region = c.region
                }
            }
        }
    }
}
