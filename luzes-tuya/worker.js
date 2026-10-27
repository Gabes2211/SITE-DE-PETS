// Luzes Tuya: liga e desliga lâmpadas Tuya/Smart Life em horários fixos.
// Roda no Cloudflare Workers com um Cron Trigger a cada minuto ("* * * * *").
//
// Variáveis do Worker (Settings → Variables and Secrets):
//   TUYA_ACCESS_ID      (secret) Access ID / Client ID do projeto em iot.tuya.com
//   TUYA_ACCESS_SECRET  (secret) Access Secret / Client Secret
//   CHAVE               (secret) senha que você inventa, para testar pelo navegador
//   HORARIOS            ex.: "18:00 ligar; 23:00 desligar" ou "07:00 ligar seg-sex; 08:00 desligar seg-sex"
//   FUSO                opcional, padrão America/Sao_Paulo
//   REGIAO              opcional, padrão https://openapi.tuyaus.com (Western America)
//   DISPOSITIVOS        opcional, IDs separados por vírgula; vazio = todas as lâmpadas da conta

const PADRAO = {
  HORARIOS: "18:00 ligar; 23:00 desligar",
  FUSO: "America/Sao_Paulo",
  REGIAO: "https://openapi.tuyaus.com",
};

export default {
  // Chamado pelo Cron Trigger.
  async scheduled(event, env, ctx) {
    ctx.waitUntil(rodarAgendados(event.scheduledTime, env));
  },

  // Chamado quando você abre o endereço do Worker no navegador.
  async fetch(request, env) {
    const url = new URL(request.url);
    if (!env.CHAVE || url.searchParams.get("chave") !== env.CHAVE) {
      return texto("Acesso negado. Abra com ?chave=SUA_CHAVE no final do endereço.", 403);
    }
    try {
      if (url.pathname === "/ligar") return texto(await executar(env, true));
      if (url.pathname === "/desligar") return texto(await executar(env, false));
      return texto(await resumo(env));
    } catch (e) {
      return texto("ERRO: " + e.message, 500);
    }
  },
};

// ---------------------------------------------------------------- agenda

const DIAS = { dom: 0, seg: 1, ter: 2, qua: 3, qui: 4, sex: 5, sab: 6 };
const NOMES_DIAS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];

function semAcento(s) {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

function parseDias(txt) {
  txt = semAcento(txt || "");
  if (txt === "" || txt === "todos" || txt === "todos os dias") return [0, 1, 2, 3, 4, 5, 6];
  const dias = new Set();
  for (const parte of txt.split(/[,\s]+/).filter(Boolean)) {
    const [a, b] = parte.split("-").map((s) => s.trim().slice(0, 3));
    if (!(a in DIAS) || (b !== undefined && !(b in DIAS))) {
      throw new Error(`Dia inválido: "${parte}". Use dom, seg, ter, qua, qui, sex, sab (ex.: seg-sex).`);
    }
    if (b === undefined) {
      dias.add(DIAS[a]);
    } else {
      for (let i = DIAS[a]; ; i = (i + 1) % 7) {
        dias.add(i);
        if (i === DIAS[b]) break;
      }
    }
  }
  return [...dias].sort();
}

function parseHorarios(txt) {
  const linhas = (txt || "").split(/[;\n]/).map((s) => s.trim()).filter(Boolean);
  if (linhas.length === 0) throw new Error("HORARIOS está vazio.");
  return linhas.map((linha) => {
    const m = linha.match(/^(\d{1,2})(?:[:h](\d{2})|h)\s+(ligar|desligar)\s*(.*)$/i);
    if (!m) throw new Error(`Horário inválido: "${linha}". Exemplo válido: "18:00 ligar seg-sex".`);
    const hora = Number(m[1]);
    const minuto = Number(m[2] || 0);
    if (hora > 23 || minuto > 59) throw new Error(`Hora inválida: "${linha}".`);
    return { hora, minuto, ligar: m[3].toLowerCase() === "ligar", dias: parseDias(m[4]), texto: linha };
  });
}

/** Dia da semana, hora e minuto no fuso escolhido. */
function horaLocal(ms, fuso) {
  const partes = new Intl.DateTimeFormat("en-US", {
    timeZone: fuso,
    hourCycle: "h23",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
  }).formatToParts(new Date(ms));
  const p = Object.fromEntries(partes.map((x) => [x.type, x.value]));
  const dia = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }[p.weekday];
  return { dia, hora: Number(p.hour) % 24, minuto: Number(p.minute) };
}

/** Horários que batem com este minuto (o último da lista vence se houver dois). */
function acaoAgora(horarios, agora) {
  const iguais = horarios.filter(
    (h) => h.hora === agora.hora && h.minuto === agora.minuto && h.dias.includes(agora.dia),
  );
  return iguais.length ? iguais[iguais.length - 1] : null;
}

async function rodarAgendados(ms, env) {
  try {
    const fuso = env.FUSO || PADRAO.FUSO;
    const horario = acaoAgora(parseHorarios(env.HORARIOS || PADRAO.HORARIOS), horaLocal(ms, fuso));
    if (!horario) return;
    console.log(`Horário "${horario.texto}" disparou.`);
    console.log(await executar(env, horario.ligar));
  } catch (e) {
    console.error("Falha no agendamento: " + e.message);
  }
}

// ---------------------------------------------------------------- ações

async function executar(env, ligar) {
  const tuya = new Tuya(env);
  const lampadas = await escolherLampadas(tuya, env);
  if (lampadas.length === 0) return "Nenhuma lâmpada encontrada na conta vinculada.";
  const linhas = await Promise.all(
    lampadas.map(async (d) => {
      try {
        await comRetentativa(() =>
          tuya.req("POST", `/v1.0/devices/${d.id}/commands`, {
            body: { commands: [{ code: codigoSwitch(d), value: ligar }] },
          }),
        );
        return `OK    ${d.name}`;
      } catch (e) {
        return `FALHA ${d.name}: ${e.message}`;
      }
    }),
  );
  return `${ligar ? "Ligar" : "Desligar"} (${lampadas.length} lâmpada(s)):\n` + linhas.join("\n");
}

async function resumo(env) {
  const fuso = env.FUSO || PADRAO.FUSO;
  const horarios = parseHorarios(env.HORARIOS || PADRAO.HORARIOS);
  const agora = horaLocal(Date.now(), fuso);
  const tuya = new Tuya(env);
  const todos = await tuya.listarDispositivos();
  const escolhidas = new Set((await escolherLampadas(tuya, env, todos)).map((d) => d.id));

  const pad = (n) => String(n).padStart(2, "0");
  const out = [];
  out.push(`Conectado à Tuya. Agora: ${NOMES_DIAS[agora.dia]} ${pad(agora.hora)}:${pad(agora.minuto)} (${fuso})`);
  out.push("");
  out.push("Horários:");
  for (const h of horarios) {
    const dias = h.dias.length === 7 ? "todos os dias" : h.dias.map((d) => NOMES_DIAS[d]).join(", ");
    out.push(`  ${pad(h.hora)}:${pad(h.minuto)}  ${h.ligar ? "LIGAR   " : "DESLIGAR"}  ${dias}`);
  }
  out.push("");
  out.push("Dispositivos ([x] = controlado pelos horários):");
  for (const d of todos) {
    const estado = estadoSwitch(d);
    out.push(
      `  [${escolhidas.has(d.id) ? "x" : " "}] ${d.name}` +
        `  ${estado === undefined ? "" : estado ? "(ligada)" : "(desligada)"}` +
        `${d.online === false ? " OFFLINE" : ""}  id=${d.id}`,
    );
  }
  out.push("");
  out.push("Teste agora: troque o fim do endereço por /ligar?chave=... ou /desligar?chave=...");
  return out.join("\n");
}

async function escolherLampadas(tuya, env, todos) {
  todos = todos || (await tuya.listarDispositivos());
  const ids = (env.DISPOSITIVOS || "").split(",").map((s) => s.trim()).filter(Boolean);
  if (ids.length) return todos.filter((d) => ids.includes(d.id));
  // Sem lista: todas as lâmpadas (dispositivos com o comando "switch_led").
  return todos.filter((d) => (d.status || []).some((s) => s.code === "switch_led"));
}

function codigoSwitch(d) {
  const codes = (d.status || []).map((s) => s.code);
  return ["switch_led", "switch_1", "switch"].find((c) => codes.includes(c)) || "switch_led";
}

function estadoSwitch(d) {
  const s = (d.status || []).find((s) => s.code === codigoSwitch(d));
  return s ? s.value : undefined;
}

async function comRetentativa(fn, tentativas = 3) {
  for (let i = 1; ; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i >= tentativas) throw e;
      await new Promise((r) => setTimeout(r, 3000 * i));
    }
  }
}

// ---------------------------------------------------------------- Tuya API

class Tuya {
  constructor(env) {
    if (!env.TUYA_ACCESS_ID || !env.TUYA_ACCESS_SECRET) {
      throw new Error("Faltam as variáveis TUYA_ACCESS_ID e TUYA_ACCESS_SECRET.");
    }
    this.id = env.TUYA_ACCESS_ID.trim();
    this.secret = env.TUYA_ACCESS_SECRET.trim();
    this.base = (env.REGIAO || PADRAO.REGIAO).trim().replace(/\/$/, "");
    this.token = null;
  }

  async getToken() {
    if (!this.token) {
      const r = await this.req("GET", "/v1.0/token", { query: { grant_type: "1" }, auth: false });
      this.token = r.access_token;
    }
    return this.token;
  }

  async listarDispositivos() {
    const todos = [];
    let lastRowKey;
    do {
      const query = { size: "50" };
      if (lastRowKey) query.last_row_key = lastRowKey;
      const r = await this.req("GET", "/v1.0/iot-01/associated-users/devices", { query });
      todos.push(...(r.devices || []));
      lastRowKey = r.has_more ? r.last_row_key : null;
    } while (lastRowKey);
    return todos.sort((a, b) => a.name.localeCompare(b.name));
  }

  async req(method, path, { query, body, auth = true } = {}) {
    const token = auth ? await this.getToken() : "";
    const qs = query ? Object.keys(query).sort().map((k) => `${k}=${query[k]}`).join("&") : "";
    const caminho = qs ? `${path}?${qs}` : path;
    const corpo = body ? JSON.stringify(body) : "";

    // Assinatura Tuya: HMAC-SHA256(client_id + access_token + t + stringToSign)
    // stringToSign = METHOD \n SHA256(corpo) \n (headers vazios) \n caminho
    const t = Date.now().toString();
    const stringToSign = [method, await sha256Hex(corpo), "", caminho].join("\n");
    const sign = (await hmacHex(this.secret, this.id + token + t + stringToSign)).toUpperCase();

    const headers = { client_id: this.id, sign, sign_method: "HMAC-SHA256", t, lang: "pt" };
    if (auth) headers.access_token = token;
    if (body) headers["Content-Type"] = "application/json";

    const resp = await fetch(this.base + caminho, { method, headers, body: body ? corpo : undefined });
    const json = await resp.json();
    if (!json.success) throw new Error(`Tuya ${json.code}: ${json.msg}${dica(json)}`);
    return json.result;
  }
}

function dica(json) {
  const msg = String(json.msg || "").toLowerCase();
  const code = String(json.code);
  if (msg.includes("permission") || code === "28841105") {
    return " (autorize o serviço IoT Core no projeto da Tuya, ou renove o Trial)";
  }
  if (msg.includes("sign") || code === "1004" || code === "1106") {
    return " (confira Access ID/Secret e se a REGIAO é o data center do projeto)";
  }
  return "";
}

async function sha256Hex(texto) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return hex(buf);
}

async function hmacHex(chave, texto) {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(chave), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(texto)));
}

function hex(buf) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function texto(body, status = 200) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
