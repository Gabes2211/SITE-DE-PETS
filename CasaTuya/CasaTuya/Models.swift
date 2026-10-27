import Foundation

/// Valor JSON genérico (os "status" da Tuya podem ser bool, número, texto...).
enum JSONValue: Codable, Hashable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

enum TuyaRegion: String, Codable, CaseIterable, Identifiable {
    case americaOeste = "https://openapi.tuyaus.com"
    case americaLeste = "https://openapi-ueaz.tuyaus.com"
    case europaCentral = "https://openapi.tuyaeu.com"
    case europaOeste = "https://openapi-weaz.tuyaeu.com"
    case china = "https://openapi.tuyacn.com"
    case india = "https://openapi.tuyain.com"

    var id: String { rawValue }

    var nome: String {
        switch self {
        case .americaOeste: return "Western America (Brasil normalmente)"
        case .americaLeste: return "Eastern America"
        case .europaCentral: return "Central Europe"
        case .europaOeste: return "Western Europe"
        case .china: return "China"
        case .india: return "India"
        }
    }
}

struct TuyaCredentials: Codable, Equatable {
    var accessId: String
    var accessSecret: String
    var region: TuyaRegion
}

struct DeviceStatus: Codable, Hashable {
    let code: String
    var value: JSONValue
}

struct TuyaDevice: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var online: Bool?
    var category: String?
    var status: [DeviceStatus]?

    /// Código usado para ligar/desligar (lâmpadas usam "switch_led", tomadas "switch_1").
    var switchCode: String {
        let codes = (status ?? []).map(\.code)
        for candidato in ["switch_led", "switch_1", "switch"] where codes.contains(candidato) {
            return candidato
        }
        return "switch_led"
    }

    var isOn: Bool? {
        status?.first(where: { $0.code == switchCode })?.value.boolValue
    }
}

struct HoraMinuto: Codable, Hashable {
    var hora: Int
    var minuto: Int

    var texto: String { String(format: "%02d:%02d", hora, minuto) }

    var date: Date {
        get { Calendar.current.date(bySettingHour: hora, minute: minuto, second: 0, of: Date()) ?? Date() }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hora = c.hour ?? 0
            minuto = c.minute ?? 0
        }
    }
}

/// Uma rotina = "ligar às X, desligar às Y, nesses dias, nessas lâmpadas".
/// Ela vira timers na nuvem da Tuya, que rodam mesmo com o iPhone desligado.
struct Rotina: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var nome: String
    var deviceIds: [String]
    var ligar: HoraMinuto?
    var desligar: HoraMinuto?
    /// 1 = domingo ... 7 = sábado (igual ao Calendar do iOS).
    var dias: Set<Int> = Set(1...7)

    /// Prefixo gravado no nome do timer na nuvem, para achar e apagar depois.
    var tag: String { "CT" + String(id.replacingOccurrences(of: "-", with: "").prefix(8)) }

    /// Formato da Tuya: 7 dígitos, o primeiro é domingo. Ex.: "0111110" = seg a sex.
    var loops: String { (1...7).map { dias.contains($0) ? "1" : "0" }.joined() }

    var resumoDias: String {
        if dias.count == 7 { return "Todos os dias" }
        if dias == Set(2...6) { return "Seg a sex" }
        if dias == [1, 7] { return "Fins de semana" }
        let nomes = Calendar.current.shortWeekdaySymbols
        return dias.sorted().map { nomes[$0 - 1] }.joined(separator: ", ")
    }
}

/// Timer como a nuvem da Tuya devolve.
struct TimerNuvem: Identifiable, Hashable {
    let id: String
    let alias: String
    let time: String
    let loops: String
    let ativo: Bool
    let descricao: String

    init?(json: JSONValue) {
        guard let id = (json["timer_id"] ?? json["id"])?.stringValue else { return nil }
        self.id = id
        alias = json["alias_name"]?.stringValue ?? ""
        time = json["time"]?.stringValue ?? "--:--"
        loops = json["loops"]?.stringValue ?? ""
        if let s = json["status"] {
            ativo = s.boolValue ?? (s.stringValue != "0")
        } else {
            ativo = true
        }
        let fns = json["functions"]?.arrayValue ?? []
        descricao = fns.compactMap { f -> String? in
            guard let code = f["code"]?.stringValue else { return nil }
            if let b = f["value"]?.boolValue { return b ? "Ligar" : "Desligar" }
            return "\(code)=\(f["value"]?.stringValue ?? "?")"
        }.joined(separator: ", ")
    }
}
