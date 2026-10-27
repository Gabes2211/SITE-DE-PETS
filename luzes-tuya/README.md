# Luzes Tuya: liga e desliga as lâmpadas em horários fixos

Um programinha (`worker.js`) que roda **de graça na nuvem da Cloudflare**. A cada minuto ele
confere o relógio e, no horário marcado, manda a Tuya ligar ou desligar as lâmpadas.
Não depende do iPhone, de computador nem do agendamento do app da Tuya.

Dá para fazer tudo pelo navegador do celular. Leva uns 20 minutos, só uma vez.

---

## Parte 1: acesso à API da Tuya

1. Abra <https://iot.tuya.com> e crie uma conta (grátis). Se o site pedir, use a versão para
   computador do navegador (no Safari: **aA** → *Solicitar Site para Computador*).
2. **Cloud → Development → Create Cloud Project**
   - *Development Method*: **Smart Home**
   - *Data Center*: **Western America** (é o das contas criadas no Brasil; se suas lâmpadas
     não aparecerem no passo 4, refaça com outro data center).
3. Na tela seguinte, autorize **IoT Core** e **Authorization Token Management**.
   (Se pulou: projeto → aba *Service API* → *Go to Authorize*.)
4. No projeto: **Devices → Link App Account → Add App Account**. Aparece um QR code.
   No app **Smart Life/Tuya**: aba *Eu/Perfil* → ícone de escanear no canto superior → leia o QR.
   Suas lâmpadas devem aparecer na lista *All Devices* do projeto.
   - Dica: se estiver tudo no mesmo celular, tire um print do QR e mande para outro aparelho,
     ou abra o site num computador emprestado só para esse passo.
5. Na aba **Overview**, copie o **Access ID/Client ID** e o **Access Secret/Client Secret**.

## Parte 2: criar o Worker na Cloudflare

1. Crie uma conta grátis em <https://dash.cloudflare.com/sign-up>.
2. Menu **Workers & Pages** (ou *Compute → Workers*) → **Create** → **Create Worker**
   (modelo "Hello World") → dê o nome `luzes-casa` → **Deploy**.
3. Clique em **Edit code**. Apague todo o código que está lá, cole o conteúdo inteiro de
   [`worker.js`](worker.js) e clique em **Deploy**.
4. Volte ao Worker → **Settings → Variables and Secrets → Add**:

   | Nome | Tipo | Valor |
   | --- | --- | --- |
   | `TUYA_ACCESS_ID` | Secret | o Access ID da Parte 1 |
   | `TUYA_ACCESS_SECRET` | Secret | o Access Secret da Parte 1 |
   | `CHAVE` | Secret | uma senha que você inventa (ex.: `lampada-azul-42`) |
   | `HORARIOS` | Text | ex.: `18:00 ligar; 23:00 desligar` |

   Clique em **Deploy** (ou *Save*) no final.
5. **Settings → Trigger Events** (ou *Triggers*) → **Add → Cron Triggers** →
   escolha *Minutes* / "a cada 1 minuto", ou digite `* * * * *` → **Add**.

Pronto. Daqui pra frente roda sozinho.

## Parte 3: testar

Abra no navegador (troque pelo endereço do seu Worker e pela sua CHAVE):

- `https://luzes-casa.SEU-USUARIO.workers.dev/?chave=SUA_CHAVE`: mostra a hora que o
  Worker está vendo, os horários configurados e a lista de lâmpadas.
- `.../ligar?chave=SUA_CHAVE`: liga agora.
- `.../desligar?chave=SUA_CHAVE`: desliga agora.

Salve esses links nos Favoritos (ou na Tela de Início) e eles viram botões de ligar e desligar.
Para ver o que aconteceu nos horários: Worker → aba **Logs** (ative *Workers Logs* se pedir).

---

## Como escrever os horários

Variável `HORARIOS`, um horário por item, separados por `;`:

```
18:00 ligar; 23:00 desligar
```

Com dias da semana (`dom seg ter qua qui sex sab`, intervalos com `-`, listas com `,`):

```
06:30 ligar seg-sex; 07:30 desligar seg-sex; 18:00 ligar; 23:30 desligar sex,sab
```

Sem dias = todos os dias. `18h` também vale como `18:00`.

## Variáveis opcionais

| Nome | Para quê | Padrão |
| --- | --- | --- |
| `DISPOSITIVOS` | Controlar só algumas lâmpadas (ou incluir tomadas). IDs separados por vírgula; os IDs aparecem na página de teste. | todas as lâmpadas da conta |
| `FUSO` | Fuso horário. | `America/Sao_Paulo` |
| `REGIAO` | Data center da Tuya, se não for Western America: `https://openapi-ueaz.tuyaus.com` (Eastern America), `https://openapi.tuyaeu.com` (Central Europe), `https://openapi-weaz.tuyaeu.com` (Western Europe), `https://openapi.tuyain.com` (India), `https://openapi.tuyacn.com` (China). | `https://openapi.tuyaus.com` |

## Problemas comuns

| Mensagem | O que fazer |
| --- | --- |
| `Acesso negado` | Faltou `?chave=...` no endereço, ou está diferente da variável `CHAVE`. |
| `Tuya 1004` / `sign invalid` | Access ID/Secret copiado errado ou `REGIAO` diferente do data center do projeto. |
| `Tuya 28841105` / `No permissions` | Autorize *IoT Core* no projeto ou renove o período grátis (abaixo). |
| `Nenhuma lâmpada encontrada` | Faltou o *Link App Account* ou o data center está errado. Se o seu aparelho não for reconhecido como lâmpada, use `DISPOSITIVOS` com o id dele. |
| Lâmpada aparece `OFFLINE` | Ela está sem Wi-Fi ou sem energia; a nuvem não alcança. |

## Manutenção

- **Renovar o plano grátis da Tuya.** O serviço IoT Core é gratuito, mas o período de teste vence
  (normalmente entre 1 e 6 meses). A Tuya manda e-mail antes. Para renovar: iot.tuya.com →
  *Cloud → Cloud Services → IoT Core* → **Extend Trial Period**. Se vencer, as lâmpadas param de
  obedecer ao Worker até você renovar.
- **Custo.** A Cloudflare grátis permite 100 mil execuções por dia; rodar a cada minuto usa 1.440.
