# Casa – controle das lâmpadas Tuya no iPhone

App iOS (SwiftUI) que conversa direto com a **API Cloud da Tuya** para:

- ver e ligar/desligar suas lâmpadas Tuya / Smart Life;
- criar **rotinas** ("ligar às 18:00, desligar às 23:00, seg a sex");
- oferecer os atalhos **Ligar lâmpadas** / **Desligar lâmpadas** para a Siri e o app Atalhos.

## Como os horários funcionam (importante)

O iOS não deixa um app acordar sozinho num horário exato. Por isso o app usa dois caminhos:

1. **Timers na nuvem da Tuya (principal).** Ao salvar uma rotina, o app cria timers nos
   servidores da Tuya. Quem liga e desliga a lâmpada é a nuvem, então funciona com o iPhone
   desligado ou sem internet. Na tela da rotina dá para conferir se os timers estão lá.
2. **Automação do app Atalhos (plano B).** Atalhos → Automação → **+** → *Horário do Dia* →
   escolha a hora → ação **Ligar lâmpadas** (do app Casa) → marque **Executar imediatamente**.
   Faça outra para **Desligar lâmpadas**. Essa precisa do iPhone ligado e com internet.

## 1. Criar o acesso à API da Tuya (uma vez só, ~10 min)

1. Entre em <https://iot.tuya.com> e crie uma conta (pode ser grátis).
2. **Cloud → Development → Create Cloud Project**
   - Development Method: *Smart Home*
   - Data Center: o mesmo da sua conta do app. Para contas criadas no Brasil normalmente é
     **Western America**.
3. Na criação, autorize os serviços **IoT Core** e **Authorization Token Management**
   (se esquecer: projeto → *Service API* → *Go to Authorize*).
4. Projeto → **Devices → Link App Account → Add App Account**. Aparece um QR code: no app
   Smart Life/Tuya, toque no ícone de escanear (canto superior) e leia o código. Suas lâmpadas
   passam a aparecer no projeto.
5. Em **Overview** copie o **Access ID/Client ID** e o **Access Secret/Client Secret**.

> O plano grátis (Trial) do IoT Core expira depois de um tempo; renove em
> *Cloud → Cloud Services → IoT Core → Extend Trial Period* (é gratuito).

## 2. Instalar o app no iPhone

Precisa de um Mac com Xcode 15 ou mais novo. Uma Apple ID gratuita já serve (o app vale por 7 dias e
depois é só rodar de novo pelo Xcode; com a conta de desenvolvedor paga, vale 1 ano).

**Opção A, com XcodeGen:**

```bash
brew install xcodegen
cd CasaTuya
xcodegen          # gera CasaTuya.xcodeproj a partir do project.yml
open CasaTuya.xcodeproj
```

**Opção B, sem XcodeGen:** no Xcode, *File → New → Project → iOS App* (Interface: SwiftUI,
nome `CasaTuya`), apague o `ContentView.swift` e o `CasaTuyaApp.swift` gerados e arraste
todos os arquivos da pasta `CasaTuya/CasaTuya/` para o projeto.

Depois, nos dois casos:

1. Clique no projeto → *Signing & Capabilities* → escolha seu **Team** (sua Apple ID) e,
   se reclamar, troque o Bundle Identifier (ex.: `com.seunome.casatuya`).
2. Conecte o iPhone, selecione-o lá em cima e aperte ▶︎.
3. No iPhone: *Ajustes → Geral → VPN e Gerenciamento de Dispositivo* → confie no seu perfil de
   desenvolvedor. Na primeira vez também é preciso ativar o *Modo de Desenvolvedor*
   (*Ajustes → Privacidade e Segurança*).

## 3. Usar

1. Aba **Ajustes**: cole o Access ID e o Secret, escolha o data center e toque em
   *Salvar e conectar*. As lâmpadas aparecem na aba **Lâmpadas**.
2. Aba **Rotinas** → **+**: horário de ligar, de desligar, dias e lâmpadas → *Salvar*.
3. Abra a rotina para conferir os timers confirmados na nuvem.

## Problemas comuns

| Mensagem | O que fazer |
| --- | --- |
| `sign invalid` / `1004` / `1106` | Access ID/Secret errado ou data center diferente do da sua conta. |
| `No permissions` / `28841105` | Autorize *IoT Core* no projeto (Service API) ou renove o Trial. |
| Lista de lâmpadas vazia | Faltou o passo *Link App Account* ou o data center está errado. |
| Rotina criada mas a tela mostra "Nenhum timer encontrado" | Apague e recrie; se continuar, use o plano B (Atalhos). |

## Arquivos

- `TuyaClient.swift`: chamadas à API Tuya (token, assinatura HMAC-SHA256, comandos, timers).
- `AppStore.swift`: estado do app, rotinas e lógica dos atalhos.
- `ContentView.swift`: telas (Lâmpadas, Rotinas, Ajustes).
- `Atalhos.swift`: ações para a Siri e o app Atalhos.
- `Keychain.swift`: guarda as credenciais com segurança no iPhone.
