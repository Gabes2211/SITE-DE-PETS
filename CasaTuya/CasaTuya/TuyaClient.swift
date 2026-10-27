import CryptoKit
import Foundation

enum TuyaError: LocalizedError {
    case semCredenciais
    case api(code: String, msg: String)
    case respostaInvalida

    var errorDescription: String? {
        switch self {
        case .semCredenciais:
            return "Configure o Access ID e o Access Secret na aba Ajustes."
        case .respostaInvalida:
            return "Resposta inesperada da Tuya."
        case .api(let code, let msg):
            var texto = "Tuya (\(code)): \(msg)"
            if msg.lowercased().contains("permission") || code == "28841105" {
                texto += "\n\nNo projeto da Tuya IoT Platform, abra Service API e autorize \"IoT Core\" (e \"Authorization Token Management\")."
            } else if code == "1106" || msg.lowercased().contains("sign") {
                texto += "\n\nConfira o Access ID/Secret e o data center escolhido."
            }
            return texto
        }
    }
}

/// Cliente da API Cloud da Tuya (OpenAPI), com a assinatura HMAC-SHA256 exigida.
actor TuyaClient {
    private var credentials: TuyaCredentials?
    private var token: String?
    private var tokenExpira = Date.distantPast
    private let session = URLSession(configuration: .default)

    init(credentials: TuyaCredentials?) {
        self.credentials = credentials
    }

    func setCredentials(_ c: TuyaCredentials?) {
        credentials = c
        token = nil
        tokenExpira = .distantPast
    }

    // MARK: - Endpoints

    /// Dispositivos da conta Smart Life/Tuya vinculada ao projeto.
    func listarDispositivos() async throws -> [TuyaDevice] {
        struct Pagina: Decodable {
            let devices: [TuyaDevice]
            let has_more: Bool?
            let last_row_key: String?
        }
        var todos: [TuyaDevice] = []
        var lastRowKey: String?
        repeat {
            var query = ["size": "50"]
            if let k = lastRowKey { query["last_row_key"] = k }
            let pagina: Pagina = try await call("GET", "/v1.0/iot-01/associated-users/devices", query: query)
            todos += pagina.devices
            lastRowKey = (pagina.has_more ?? false) ? pagina.last_row_key : nil
        } while lastRowKey != nil
        return todos
    }

    func status(deviceId: String) async throws -> [DeviceStatus] {
        try await call("GET", "/v1.0/devices/\(deviceId)/status")
    }

    func enviarComando(deviceId: String, code: String, value: JSONValue) async throws {
        struct Corpo: Encodable { let commands: [DeviceStatus] }
        let _: JSONValue = try await call(
            "POST", "/v1.0/devices/\(deviceId)/commands",
            body: Corpo(commands: [DeviceStatus(code: code, value: value)]))
    }

    /// Cria um timer que roda na nuvem da Tuya (não depende do iPhone).
    func criarTimer(deviceId: String, alias: String, hora: String, loops: String, code: String, value: JSONValue) async throws {
        struct Corpo: Encodable {
            let alias_name: String
            let time: String
            let timezone_id: String
            let loops: String
            let date: String?
            let functions: [DeviceStatus]
        }
        // Se nenhum dia foi escolhido, o timer roda uma vez só (hoje).
        let data: String? = loops == "0000000" ? Self.hojeYYYYMMDD() : nil
        let corpo = Corpo(alias_name: alias, time: hora, timezone_id: TimeZone.current.identifier,
                          loops: loops, date: data, functions: [DeviceStatus(code: code, value: value)])
        let _: JSONValue = try await call("POST", "/v2.0/cloud/timer/device/\(deviceId)", body: corpo)
    }

    func listarTimers(deviceId: String) async throws -> [TimerNuvem] {
        let r: JSONValue = try await call("GET", "/v2.0/cloud/timer/device/\(deviceId)")
        // A resposta pode vir como lista direta ou dentro de "list"/"timers".
        let lista = r.arrayValue ?? r["list"]?.arrayValue ?? r["timers"]?.arrayValue ?? []
        return lista.compactMap(TimerNuvem.init(json:))
    }

    func apagarTimers(deviceId: String, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let _: JSONValue = try await call(
            "DELETE", "/v2.0/cloud/timer/device/\(deviceId)/batch",
            query: ["timer_ids": ids.joined(separator: ",")])
    }

    // MARK: - Infra

    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool
        let result: T?
        let code: JSONValue?
        let msg: String?
    }

    private func tokenValido() async throws -> String {
        if let token, Date() < tokenExpira { return token }
        struct TokenResult: Decodable { let access_token: String; let expire_time: Double }
        let r: TokenResult = try await call("GET", "/v1.0/token", query: ["grant_type": "1"], autenticado: false)
        token = r.access_token
        tokenExpira = Date().addingTimeInterval(r.expire_time - 60)
        return r.access_token
    }

    private func call<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:],
                                    body: (any Encodable)? = nil, autenticado: Bool = true,
                                    tentativa: Int = 0) async throws -> T {
        guard let credentials, !credentials.accessId.isEmpty, !credentials.accessSecret.isEmpty else {
            throw TuyaError.semCredenciais
        }
        let accessToken = autenticado ? try await tokenValido() : ""

        let queryString = query.keys.sorted().map { "\($0)=\(query[$0]!)" }.joined(separator: "&")
        let urlPath = queryString.isEmpty ? path : "\(path)?\(queryString)"
        let bodyData = try body.map { try JSONEncoder().encode($0) } ?? Data()

        // Assinatura Tuya: client_id + access_token + t + stringToSign
        // stringToSign = METHOD \n SHA256(body) \n (headers vazios) \n url
        let t = String(Int64(Date().timeIntervalSince1970 * 1000))
        let bodyHash = SHA256.hash(data: bodyData).map { String(format: "%02x", $0) }.joined()
        let stringToSign = "\(method)\n\(bodyHash)\n\n\(urlPath)"
        let mensagem = credentials.accessId + accessToken + t + stringToSign
        let chave = SymmetricKey(data: Data(credentials.accessSecret.utf8))
        let sign = HMAC<SHA256>.authenticationCode(for: Data(mensagem.utf8), using: chave)
            .map { String(format: "%02X", $0) }.joined()

        let encoded = urlPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlPath
        guard let url = URL(string: credentials.region.rawValue + encoded) else { throw TuyaError.respostaInvalida }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(credentials.accessId, forHTTPHeaderField: "client_id")
        req.setValue(sign, forHTTPHeaderField: "sign")
        req.setValue("HMAC-SHA256", forHTTPHeaderField: "sign_method")
        req.setValue(t, forHTTPHeaderField: "t")
        req.setValue("pt", forHTTPHeaderField: "lang")
        if autenticado { req.setValue(accessToken, forHTTPHeaderField: "access_token") }
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData
        }

        let (data, _) = try await session.data(for: req)
        guard let env = try? JSONDecoder().decode(Envelope<T>.self, from: data) else {
            if let generico = try? JSONDecoder().decode(Envelope<JSONValue>.self, from: data), !generico.success {
                throw TuyaError.api(code: generico.code?.stringValue ?? "?", msg: generico.msg ?? "erro desconhecido")
            }
            throw TuyaError.respostaInvalida
        }
        if env.success, let result = env.result { return result }

        let code = env.code?.stringValue ?? "?"
        // Token expirado/inválido: pega outro e tenta de novo uma vez.
        if autenticado, tentativa == 0, ["1010", "1011"].contains(code) {
            token = nil
            return try await call(method, path, query: query, body: body, autenticado: true, tentativa: 1)
        }
        throw TuyaError.api(code: code, msg: env.msg ?? "erro desconhecido")
    }

    private static func hojeYYYYMMDD() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}
