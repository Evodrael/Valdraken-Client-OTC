# Guia do MiniBot (Assistant) — Client Valdraken

> Documento de referência do sistema **MiniBot / Assistant** deste client (OTClient).
> Serve tanto para **entender cada seção** quanto para **fazer modificações** no futuro.
> Ao pedir uma alteração, cite a seção/aba e, se possível, o arquivo listado no
> **Mapa de arquivos** — isso deixa a mudança muito mais direta.

Versão do MiniBot no código: **1.2.2 Beta** (`miniBotVersion = 1002002`, em [minibot.lua](minibot.lua)).

---

## 1. Visão geral

O MiniBot é um painel lateral (uma `MiniWindow`) aberto pelo botão **"Open the assistant"**
(o `button_minibot`, atualmente no painel do inventário). Ele é o "assistente" de caça:
cura, ataca, equipa itens, anda por waypoints (cave bot), etc.

Conceitos centrais:

- **Presets**: conjuntos de configuração independentes. Você pode ter vários presets
  (ex.: "EK Cave", "RP PvP") e alternar entre eles. Cada preset guarda a configuração de
  **todas** as seções. Há import/export por código (área de transferência).
- **Idioma**: o painel é bilíngue **pt-BR / en-US** (`getSettingsValue(false, 'language', 'ptbr')`).
  Todo texto visível é definido nas funções `reloadLanguage(language)` de cada página.
- **Módulos (features)**: cada funcionalidade (Shooter, Healing, Cave Bot...) é um "módulo"
  numerado no motor nativo `g_minibot`, ligado/desligado por `setModuleToggle(id, bool)`.
- **Armazenamento**: tudo é persistido no nó `Minibot_Settings` via `g_settings`
  (ver `_loadMiniBotSettings` / `_saveMiniBotSettings` em [minibot.lua](minibot.lua)).

### Fluxo de dados (resumido)

```
g_settings("Minibot_Settings")
 ├─ language / last_preset / <NomePersonagem>{ selected_preset, ... }
 └─ presets
     └─ "<uid>"                     -> um preset
         ├─ name / uid / creation
         ├─ combat_attack   { ... } -> aba Combat > Attack
         ├─ combat_shooter  { ... } -> aba Combat > Shooter
         ├─ combat_timers   { ... } -> aba Combat > Timers
         ├─ equipment_amulets { ... }
         ├─ equipment_rings   { ... }
         ├─ healing_health / healing_mana / healing_group { ... }
         ├─ explorer / (waypoints/sessions do recorder)
         ├─ support_main    { ... } -> aba Support > General
         └─ shortcuts       { ... } -> hotkeys/atalhos (aba Settings)
```

- Ler config do preset atual: `modules.game_minibot.getPressetSettings()`
- Gravar config no preset atual: `modules.game_minibot.setPressetSettings({ chave = valor })`
- Config global (não por preset): `getSettingsValue(false, key, default)` / `setSettingsValue(false, key, value)`
- Config por personagem: `getSettingsValue(true, key, default)` / `setSettingsValue(true, key, value)`

---

## 2. Mapa de arquivos (o que editar para cada coisa)

Base: `modules/game_minibot/`

| Arquivo | Responsabilidade |
|---|---|
| [minibot.lua](minibot.lua) | Núcleo: janela, **árvore de abas (`pages`)**, presets, idioma, import/export, saldo de gold. |
| [minibot.otui](minibot.otui) | Layout da janela principal e estilos das abas (`MiniBotInfoTab`, `MiniBotChildInfoTab`). |
| [select.otui](select.otui) | Componentes de seleção reutilizados nas páginas. |
| [minibot_editpreset.otui](minibot_editpreset.otui) | Janela de renomear preset. |
| [minibot_importpreset.otui](minibot_importpreset.otui) | Janela de importar preset/código. |
| `pages/*.lua` + `pages/*.otui` | **Uma dupla por sub-aba** (lógica + layout). |

Páginas (sub-abas) e seus arquivos em `pages/`:

| Seção → Aba | Arquivo `.lua` | Arquivo `.otui` |
|---|---|---|
| Settings | [main_settings.lua](pages/main_settings.lua) | [main_settings.otui](pages/main_settings.otui) |
| Combat → Attack | [combat_attack.lua](pages/combat_attack.lua) | [combat_attack.otui](pages/combat_attack.otui) |
| Combat → Timers | [combat_timers.lua](pages/combat_timers.lua) | [combat_timers.otui](pages/combat_timers.otui) |
| Combat → Shooter | [combat_shooter.lua](pages/combat_shooter.lua) | [combat_shooter.otui](pages/combat_shooter.otui) |
| Combat → PvP | [combat_pvp.lua](pages/combat_pvp.lua) | [combat_pvp.otui](pages/combat_pvp.otui) |
| Equipment → Amulets | [equipment_amulets.lua](pages/equipment_amulets.lua) | [equipment_amulets.otui](pages/equipment_amulets.otui) |
| Equipment → Rings | [equipment_rings.lua](pages/equipment_rings.lua) | [equipment_rings.otui](pages/equipment_rings.otui) |
| Cave Bot → Recorder | [hunting_recorder.lua](pages/hunting_recorder.lua) | [hunting_recorder.otui](pages/hunting_recorder.otui) |
| Cave Bot → Explorer | [hunting_explorer.lua](pages/hunting_explorer.lua) | [hunting_explorer.otui](pages/hunting_explorer.otui) |
| Healing → Health | [healing_health.lua](pages/healing_health.lua) | [healing_health.otui](pages/healing_health.otui) |
| Healing → Mana | [healing_mana.lua](pages/healing_mana.lua) | [healing_mana.otui](pages/healing_mana.otui) |
| Healing → Group | [healing_group.lua](pages/healing_group.lua) | [healing_group.otui](pages/healing_group.otui) |
| Support → General | [support_general.lua](pages/support_general.lua) | [support_general.otui](pages/support_general.otui) |
| Support → Mana Shield | [support_manashield.lua](pages/support_manashield.lua) | [support_manashield.otui](pages/support_manashield.otui) |

> O **botão que abre o assistente** (`button_minibot`) fica em
> `modules/game_inventory/inventory.otui` e chama `modules.game_inventory.toggleAssistant()`.
> O toggle final chama `modules.game_minibot.toggle()`.

A ordem e o agrupamento das abas são definidos pela tabela `pages` em
[minibot.lua](minibot.lua) (aprox. linhas 63–247). É lá que se adiciona/remove/reordena
seções e sub-abas.

---

## 3. Como o motor funciona (nativo `g_minibot`)

O `g_minibot` é a parte em C++ (bindings em `src/client/luafunctions.cpp`). Funções úteis:

- `g_minibot.setModuleToggle(id, bool)` — liga/desliga uma feature.
- `g_minibot.isModuleToggle(id)` — consulta se está ligada.
- `g_minibot.cycle()` — reprocessa/aplica os módulos (chamado após trocar preset).
- `g_minibot.reset()` / `resetModule()` — zera estado.
- `g_minibot.registerWalkWaypoint(...)`, `setCurrentWalkIndex`, `setExplorerWalker`,
  `resetRecorderSession`, `getAreaCoordinates` — usados pelo Cave Bot.

### Tabela de IDs de módulo (toggles)

Extraída dos `setModuleToggle(...)` de cada página. Útil ao mexer no liga/desliga:

| ID | Feature | Página |
|---:|---|---|
| 0 | Shooter | combat_shooter |
| 1 | Healing Health | healing_health |
| 2 | Healing Mana | healing_mana |
| 3 | Combat Timers | combat_timers |
| 5 | Cave Bot (Recorder) | hunting_recorder |
| 6 | Healing Group (mestre) | healing_group / main_settings |
| 9 | Auto Attack (liga/desliga) | main_settings + combat_attack |
| 10 | Equipment Amulets | equipment_amulets |
| 11 | Equipment Rings | equipment_rings |
| 16 | PvP: Tank Mode | combat_pvp |
| 17 | PvP: Auto-remove Paralyze | combat_pvp |
| 18–20 | Healing Group (listas internas) | healing_group |
| 21 | Cave Bot Explorer | hunting_explorer |
| 23 | Ammo Refill (recarga de munição) | combat_attack |

> **Auto Attack** é especial: o *modo* de alvo (closest/lowest/highest/smart) vem de
> `g_minibot.setAutoAttack(type)` (type: 1=closest, 2=lowest, 3=highest, 200=smart; +100 = só
> melee), e o *liga/desliga* é o **módulo 9** (`ModuleAutoAttack`). O motor
> (`processAutoAttack`) exige **as duas coisas**: `m_autoAttack > 0` **E** módulo 9 ligado.
> Por isso `combat_attack.reloadInternalModule` sincroniza os dois juntos — se separá-los,
> o auto-attack passa a funcionar só "às vezes".

### Gancho de login (`onPlayerInfo`)

`onPlayerInfo()` é o que seleciona o preset do personagem no login (via `onClickPresetEntry`),
recarrega os módulos e rebinda as hotkeys. **Ele é disparado por `connect(g_game, { onGameStart
= onPlayerInfo })`** em [minibot.lua](minibot.lua).

> Historicamente o connect era `onPlayerInfo = onPlayerInfo`, que nunca disparava: o C++ **não
> emite** `g_game.onPlayerInfo` (o `parsePlayerInfo` só seta premium/vocação/spells, sem
> `callGlobalField`). Como o módulo carrega no startup ainda offline, o `if g_game.isOnline()`
> do `init()` também era falso. Resultado: nenhum preset ficava com `selectedPreset = true`, o
> `getPressetSettings()` devolvia `{}` e **o Assistente não aplicava nada até o jogador abrir a
> janela e clicar num preset**. Se algum recurso "só funciona depois que eu abro o Assistente",
> suspeite deste ponto.

### Padrão comum de uma página

Quase toda página `pages/<x>.lua` expõe um módulo global `game_minibot['<x>Module']` com:

- `init(panel)` — monta a página quando a aba é aberta.
- `terminate()` — desmonta ao trocar de aba.
- `reloadInternalModule()` — relê a config do preset e reaplica os toggles/valores.
- `reloadLanguage(language)` — define **todos os textos** (pt-BR/en-US).

---

## 4. Seção **Settings** (aba raiz `settings` → `main_settings`)

Duas áreas:

1. **Appearance / Aparência** — mostra/esconde o painel de atalhos do Assistente na janela
   de jogo (botão `gameWindowPanelButton`).
2. **Game Window Shortcuts / Atalhos de janela de jogo** — para cada feature você configura:
   - **Hotkey** (`.edit` / `.key`): tecla para ligar/desligar a feature.
   - **Botão na janela** (`.button`): mostra/esconde o atalho da feature na tela do jogo.

Features com atalho configurável (linhas ~320–361 de [main_settings.lua](pages/main_settings.lua)):
Auto-attack, Shooter, Health healing, Group healing, Mana healing, Combat timers,
Equipment Amulet, Equipment Ring, **Cave Bot** e **Timer do Cave Bot**.

- Persistência dos atalhos: `settings['shortcuts']` do preset.
- Também exibe a **Versão** do MiniBot (`getVersionStr()`).

---

## 5. Seção **Combat**

Sub-abas: **Attack**, **Timers**, **Shooter**, **PvP**.

### 5.1 Attack ([combat_attack.lua](pages/combat_attack.lua)) — módulo **23**
Config em `settings['combat_attack']`.
- **Atacar apenas corpo a corpo** (`meleeAttack`): só ataca criatura em alcance melee.
- **Ataque automático em criaturas próximas** (`autoAttack`): detecta o melhor alvo pela
  regra escolhida abaixo:
  - **Priorizar a posição mais próxima** (`closest`) — em empate, escolhe a de menor vida.
  - **Priorizar a vida mais baixa** (`health`).
  - **Priorizar a vida mais alta** (`highHealth`).
  - **Diamond arrow inteligente** (`smartArrow`) — melhor área de impacto da Diamond Arrow,
    priorizando menor vida.
- **Recarga de munição** (`ammoRefill`): se a munição selecionada existir no inventário,
  o sistema tenta movê-la periodicamente para a mão.

### 5.2 Timers ([combat_timers.lua](pages/combat_timers.lua)) — módulo **3**
Config em `settings['combat_timers']`. É uma **Lista de Prioridade** (Source / Action /
Monsters). Cada entrada pode ser **Spell**, **Item** ou **Comando de texto** e roda em ciclo por tempo:
- **Delay**: intervalo entre usos, **em segundos** (salvo no campo `max` da entrada).
- **Harmony**: nível mínimo de Harmony para disparar.
- **Monsters on screen**: quantidade mín./máx. de monstros na tela para disparar.
- **Ignore on PZ**: não dispara em Protection Zone.
- **Comando de texto** (campo `commandInput` na config): se preenchido (ex.: `!fps`), a
  entrada vira um comando enviado via `g_game.talk()` a cada Delay segundos, **sem precisar
  de alvo/monstro nem mana**. Salvo em `entry['command']`.

> **Delay + Comando exigem o motor (C++) atualizado.** O Lua envia `delay` (ms) e `command`
> ao motor via `g_minibot.addModule(3, ...)`, mas quem os usa é o `processAttackEntry` em
> `src/client/minibotmanager.cpp`. Historicamente o cooldown dos timers era **fixo em 1200ms**
> (o Delay do jogador era ignorado) e não existia tipo "comando". A correção lê `entry.delay`
> por entrada e adiciona o caminho de comando (dispara sem alvo). **Mudar isso requer
> recompilar o `otclient_gl_x64.exe`.**

### 5.3 Shooter ([combat_shooter.lua](pages/combat_shooter.lua)) — módulo **0**
Config em `settings['combat_shooter']`. **Lista de Prioridade** de spells/runas de ataque em área/alvo:
- **Creatures on range**: dispara quando N criaturas estiverem dentro da área do spell/runa.
- **Health**: só dispara se sua vida estiver **abaixo** do valor.
- **Mana**: só dispara se sua mana estiver **acima** do valor.
- **Harmony**: requisito de Harmony.
- **Extended area**: considera a área estendida do spell (Wheel of Destiny).
- **Smart attack** (`autoRotate`): gira o personagem para acertar o maior número de alvos.
- **Preview**: mostra a área afetada do spell/runa selecionado.

### 5.4 PvP ([combat_pvp.lua](pages/combat_pvp.lua)) — módulos **16** e **17**
- **Tank mode (SSA and Might Ring)** (`tankMode`, módulo 16): equipa automaticamente
  Stone Skin Amulet e Might Ring quando possível.
- **Auto-remove paralyze** (`antiParalyze`, módulo 17): lança um dos spells selecionados
  assim que você é paralisado (prioridade da esquerda para a direita).

---

## 6. Seção **Equipment**

Sub-abas: **Amulets** e **Rings**. Estrutura idêntica; mudam só o slot e a chave de settings.

### 6.1 Amulets ([equipment_amulets.lua](pages/equipment_amulets.lua)) — módulo **10**
Config em `settings['equipment_amulets']`. **Lista de Prioridade** de amuletos a equipar/desequipar
conforme condições:
- **Health (Min/Max)**: equipa/desequipa quando sua vida está acima (Min) ou abaixo (Max).
- **Mana (Min/Max)**: idem para mana.
- **Unequip**: entrada só para desequipar.
- **Ignore when**: lista de itens que, se equipados, fazem o Assistente ignorar a entrada.
- **Harmony**: requisito de Harmony por entrada.

### 6.2 Rings ([equipment_rings.lua](pages/equipment_rings.lua)) — módulo **11**
Config em `settings['equipment_rings']`. Mesma lógica dos amuletos, aplicada ao slot de anel.

---

## 7. Seção **Cave Bot** (aba raiz `cavebot`)

Sub-abas: **Recorder** e **Explorer**. É o sistema de movimentação automática.

### 7.1 Recorder ([hunting_recorder.lua](pages/hunting_recorder.lua)) — módulo **5**
Grava e reproduz uma rota por **waypoints**. Componentes:
- **Sessions / Sessões**: cada rota gravada é uma sessão (criar, renomear, remover).
- **Map preview / Prévia do mapa**: mini-mapa com os waypoints; menu de contexto permite
  **Add walking node** (nó de caminhada) e **Add stair/teleport node** (escada/teleporte).
- **Config do waypoint selecionado**:
  - **Stop if / Parar se**: para o movimento se encontrar X monstros no campo de visão.
  - **Walk again if / Voltar a andar se**: retoma se o nº de monstros for ≤ valor (0 = respeita só o "Stop if").
  - **Velocidade entre os nodes** (`waypoint.lure`): liga/desliga a velocidade custom do node.
    Marcado usa o valor do slider; desmarcado usa a velocidade padrão (5).
  - **Velocidade** (`waypoint.speed`): valor 1–20 usado como alcance do `findPath` entre os
    nodes (maior = alcança nodes mais distantes por passo).

> **Estas quatro configs são do motor (C++), não do Lua.** O Lua só as envia em
> `g_minibot.registerWalkWaypoint(point)`; quem decide é o `processCaveBot` em
> `src/client/minibotmanager.cpp`. **Mexer nelas exige recompilar o exe.**
>
> - **Stop if / Walk again if** (`waypoint.creatures` / `waypoint.resume`): historicamente eram
>   lidas para o struct `Waypoint` e **nunca usadas** — o `processCaveBot` andava incondicionalmente,
>   então a config não fazia absolutamente nada. Implementadas em jul/2026 com a mesma histerese do
>   `processExplorer`: segura o passo quando `nearbyHostileCount(localPlayer, 7) >= creatures` e só
>   solta quando cai para `<= resume` (`resume = 0` → solta assim que ficar abaixo de `creatures`).
>   O teste fica **depois** da checagem de chegada, para que parar em cima de um nó ainda avance a rota.
> - **`waypoint.lure` agora é o toggle de velocidade custom** (rótulo "Velocidade entre os nodes").
>   O motor continua sem ler `lure`; a decisão fica no Lua: `resolveNodeSpeed` envia `waypoint.speed`
>   quando `lure` está marcado, senão envia a velocidade padrão (`DEFAULT_NODE_SPEED = 5`). O
>   `findPath` usa esse valor como alcance. (O `lure` do **Explorer** — `cfg.use` — é outra coisa.)
  - **Overwrite to all / Alterar para todos**: aplica a config deste waypoint a todos.
- **Renovar 1 hora**: compra 1h de tempo de cave bot (`g_game.afkPause(4)`).
- **Import/Export**: rota exportável por código (versão via `getExportCodeVersion()`).

> **O "AFK Pause (5 min)" foi removido** do painel. `g_game.afkPause(action)` continua sendo o
> canal de várias ações do cave bot (ver `Game::afkPause`): **0**=limpa pausa AFK, **1**=pausa
> 5min, **2**=task on, **3**=task off, **4**=renova. Só o **1** deixou de ser usado — o **4** é o
> botão de renovar e o **0** segue no `init` da página, porque o servidor responde com o estado
> novo do cave bot e é assim que o timer se atualiza ao abrir a aba. Para pedir o estado sem
> efeito colateral existe `g_game.requestCaveBot()` (action **6**), usado no login.

> Restrição de servidor: se o jogador for banido do cavebot, aparece a mensagem de proibição
> com data/hora (o mapa fica bloqueado). Ver linhas ~241/607 de [hunting_recorder.lua](pages/hunting_recorder.lua).

### 7.2 Explorer ([hunting_explorer.lua](pages/hunting_explorer.lua)) — módulo **21**
Config em `settings['explorer']`. Caça **sem rota gravada** (anda pela área). O modo **Lure** foi
removido — só existe **Correr e parar**:
- **Run and stop / Correr e parar**: anda em velocidade normal até encontrar N monstros.
  Enviado ao motor sempre com `use = false`. Desligado, o personagem apenas vagueia.
- **Stop if find X monsters**: nº mínimo de monstros para parar e atacar (0 = não para).
- **After stop, walk if X monsters**: nº máximo para voltar a andar (0 = respeita o "Stop if").

---

## 8. Seção **Healing**

Sub-abas: **Health**, **Mana**, **Group**. Todas são **Listas de Prioridade** com entradas
de **Spell** ou **Item**.

### 8.1 Health ([healing_health.lua](pages/healing_health.lua)) — módulo **1**
Config em `settings['healing_health']`. Cura por faixa de vida:
- **From HP**: dispara se a vida (%) estiver **acima** deste valor.
- **To HP**: dispara se a vida (%) estiver **abaixo** deste valor.
- **Harmony**: requisito de Harmony.

### 8.2 Mana ([healing_mana.lua](pages/healing_mana.lua)) — módulo **2**
Config em `settings['healing_mana']`. Igual ao Health, com **From MP / To MP**.

### 8.3 Group ([healing_group.lua](pages/healing_group.lua)) — módulos **6** e **18–20**
Cura de terceiros. Requer selecionar uma **lista** (ex.: `party`) antes de configurar.
- **Target**: nome do jogador alvo.
- **HP**: dispara se a vida do alvo estiver abaixo do valor.
- **Use Virtue** (`virtueOfSustain`): usa Virtue of Sustain antes de lançar o spell.

---

## 9. Seção **Support**

Sub-abas: **General** e **Mana Shield**.

### 9.1 General ([support_general.lua](pages/support_general.lua))
Config em `settings['support_main']`. Utilidades automáticas:
- **Auto change gold**: converte gold/platinum para a versão de maior valor ao acumular 100.
- **Auto mount**: ao sair de PZ, mantém a montaria ativa. *(obs.: o rótulo no código está
  como "Auto change gold" por engano — o comportamento é de montaria.)*
- **Auto Fishing** (`auto_fishing`): usa a **Mechanical Fishing Rod** (id 9306) na **Bath Tub**
  (id 26077) a cada 2 s. Os dois ids são fixos, não há seleção de item.
- **Auto training**: treina sozinho com uma exercise weapon e um tipo de dummy.
- **Auto Bless** (`auto_bless`): ao morrer, envia `!bless` automaticamente no próximo login
  **deste personagem**.
- **Auto Follow** (`auto_follow`): **anda atrás** do jogador cujo nick está no campo ao lado,
  acompanhando escadas, buracos, teleports, escadas de mão e bueiros.
- **Auto Reconnect** (`auto_reconnect`): se a conexão cair, refaz o login do personagem.

> **O Auto Reconnect não é implementado aqui.** Quem reconecta é o `client_entergame`. O MiniBot
> só **liga a chave** (setting global `autoReconnect` + flag por personagem via `saveAutoReconnect`).
>
> `reloadSupportRuntime` grava **os dois** stores, e ambos são necessários: o reconnect lê o flag
> **por personagem**, mas o `onLogout` do `characterlist.lua` **sobrescreve** esse flag a partir do
> setting **global** `autoReconnect`. Gravar só um dos dois é desfeito silenciosamente.
>
> **Reconexão persistente (jul/2026):** os disparos-únicos antigos (`scheduleAutoReconnect` →
> `executeAutoReconnect`) foram substituídos por um **watchdog** em `characterlist.lua`: enquanto
> offline, com a opção ligada e sem logout manual, ele tenta `CharacterList.doLogin` **a cada 5s
> até voltar online**. É acionado por `onGameEnd`, então cobre queda de rede, **kick por idle**,
> fim de sessão limpo. **A morte** é tratada à parte em `game_playerdeath` (auto-clica "Ok",
> pois o char segue online e o watchdog não age). O **logout manual** é a única exceção — os pontos de saída em
> `game_interface/gameinterface.lua` chamam `flagManualLogout()` antes do `safeLogout`/`forceLogout`.
> O teto de 10 tentativas do `classes/login.lua` é neutralizado só nesse caminho (o watchdog zera
> `LoginEvent.loginTries` a cada ciclo); o login manual normal continua com o teto.
>
> Só religa em **queda de conexão**, não em logout manual, e só com o client aberto — a senha
> (`G.password`) vive em memória, some ao fechar.

> **Auto Bless, Auto Follow e Auto Fishing não têm módulo no motor.** Diferente das opções acima,
> elas são 100% Lua e vivem em [minibot.lua](minibot.lua), não na página — o módulo da página só
> existe enquanto a aba está aberta, e as três precisam rodar com o Assistente fechado. Lá ficam:
> `onPlayerDeath` (grava a flag `pending_bless`, por personagem e persistida, para sobreviver ao
> logout), `sendPendingBless` (chamada por `onPlayerInfo`, já com o preset selecionado), o tick
> de 1s do follow e o tick de 2s da pesca (`reloadSupportRuntime`, religado pelo
> `reloadInternalModule` da página).
>
> O tick da pesca (`autoFishingTick`) procura a vara com `g_game.findPlayerItem` — que varre os
> slots do inventário e depois os containers **abertos**, então com a mochila fechada a vara não é
> encontrada — e a Bath Tub varrendo os tiles visíveis (15x11 SQMs, mesmo andar) com
> `g_map.getTile`. Se faltar um dos dois, mostra um aviso via
> `modules.game_textmessage.displayFailureMessage`, **uma vez por motivo** (`autoFishingWarning`):
> sem esse controle o aviso repetiria a cada 2 s.

> **Auto Haste (módulo 4) e Auto Eat (módulo 8) foram removidos** do painel em jul/2026. O código
> C++ dos dois módulos continua no motor; o `reloadInternalModule` da página agora só chama
> `resetModule` + `setModuleToggle(false)` para os dois, porque os toggles são estado de sessão e
> presets antigos ainda carregam as chaves `haste` / `auto_eat` no `support_main`.
>
#### Auto Follow: como funciona (reescrito em jul/2026)

O follow **não usa mais `g_game.follow()`**. O follow do servidor é cancelado assim que o alvo
sai da tela ou troca de andar, então ele nunca acompanhava escada/teleport. Hoje o tick (250 ms,
`autoFollowTick`) **anda por conta própria** com `localPlayer:autoWalk()`, que é o mesmo caminho
do clique no mapa.

- **Mesmo andar, alvo visível**: mira no SQM **vizinho** ao alvo mais perto de nós
  (`bestFollowTile`), nunca no SQM do próprio alvo — o `findPath` trata o destino como caminhável
  mesmo ocupado, e o último passo seria recusado pelo servidor. Para de andar a 1 SQM de distância.
- **Alvo sumiu** (fora da tela, outro andar ou teleport): `autoFollowRecover` vai **pisar no SQM de
  onde ele saiu**. Escada, buraco e teleport resolvem sozinhos só de pisar. Se pisar não resolveu,
  escala: (1) mais um passo na direção em que ele andava — cobre o teleport que não chegamos a ver;
  (2) `g_game.use` no tile — escada de mão e bueiro; (3) `useWith(rope, tile)` — corda (id 3003).

> **Não há lista de ids de escada/teleport, e isso é de propósito.** A flag `hasFloorChange` do
> ThingType **só é preenchida para protocolo < 7.80**; no caminho protobuf/appearances que este
> client usa ela nunca é setada, então `Tile:hasFloorChange()` é sempre `false` aqui. E listas de id
> fixas (como as do script do zerobot que inspirou isto) são ids do **Tibia global**, que não valem
> nos assets customizados do Valdraken — é a mesma armadilha das listas de dummy do Auto Training.
> Por isso a lógica é "vá até onde ele sumiu e tente", não "identifique o tile".

Quatro detalhes que parecem opcionais e não são:

- **O rastro vem de evento, não do tick.** `onFollowCreatureMove` é conectado em `Creature`
  (`onPositionChange`) no `init()`. Um passo com haste sai em ~150 ms, abaixo do tick de 250 ms —
  amostrar a posição no tick perde SQMs, e o que se perde é justamente o degrau da escada, fazendo
  o `use` da recuperação cair no tile errado. O handler é global e sai cedo enquanto
  `followTargetName` for `nil`. Conectar em `Creature` (não em `LocalPlayer`) é o que faz o hook
  valer para instâncias `Player`, via a cadeia `Player.__index = Creature`.
- `findPlayerByName` usa `g_map.getSpectators(pos, **true**)` (multi-andar). Com `false`, subir uma
  escada seria indistinguível de sair da tela e o rastro nunca marcaria o degrau — escada de mão,
  bueiro e corda parariam de funcionar.
- `use`/corda só disparam com `followFloorHint` ligado (vimos o alvo mudar de `z`). Sem essa trava,
  o alvo apenas correr para fora da tela faria o personagem dar `use` no SQM onde ele estava —
  alavanca, porta, o que estivesse ali.
- `followWalkTo` só reemite o `autoWalk` quando o **destino muda**, com um freio de 1 s quando a
  rota falha. O `autoWalk` manda a rota inteira num pacote; chamar a cada tick vira flood de walk.

A pausa manual lê `modules.game_walking.lastManualWalk` (o módulo de andar já grava o instante de
cada passo por tecla). Registrar as teclas aqui brigaria com os binds do `game_walking`.

### 9.2 Mana Shield ([support_manashield.lua](pages/support_manashield.lua))
Aciona/renova/remove Mana Shield automaticamente. Três blocos:
- **Spell** (`spellShield`): usar spell; **Use Potion when CD**; **Renew shield** (renova
  abaixo de X%); **Force use when monsters >= N**.
- **Item** (`itemShield`): usar poção; **Use when Fear**; **Renew shield**; **Force use when monsters >= N**.
- **Remove** (`removeShield`): **Auto remove** quando as condições baterem; **Ignore when Fear**;
  **Ignore until** (segura o shield até haver ≤ N monstros).

---

## 10. Como fazer modificações (receitas)

### Adicionar uma opção (checkbox) a uma página existente
1. **Layout**: adicione o widget no `pages/<x>.otui` (ex.: um `CheckBox` com um `id`).
2. **Texto**: adicione `.setText(...)` / `.setTooltip(...)` nos dois idiomas em
   `reloadLanguage` de `pages/<x>.lua`.
3. **Persistência**: no `init` leia de `getPressetSettings()['<chave>']`; no callback do
   widget grave com `setPressetSettings({ ['<chave>'] = { ... } })`.
4. **Efeito**: em `reloadInternalModule()` aplique o valor (ex.: `g_minibot.setModuleToggle(id, valor)`).

### Adicionar uma sub-aba nova a uma seção
- Edite a tabela `pages` em [minibot.lua](minibot.lua): acrescente um item em `childs`
  com `name`, `identifier`, `icon`, `iconSize`, `ui = '<arquivo_sem_extensao>'`.
- Crie `pages/<arquivo>.lua` (com módulo `game_minibot['<arquivo>Module']` + `init`/
  `terminate`/`reloadInternalModule`/`reloadLanguage`) e `pages/<arquivo>.otui`.
- Os ícones vêm do sprite `/resources/icons_minibot` (o `icon` é um clip `x y w h`).

### Reordenar / renomear seções
- Só reordenar/renomear itens da tabela `pages` (campo `name`). Os `identifier` são usados
  em `selectMinibotPanel`, então mantenha-os estáveis se possível.

### Traduzir / mudar textos
- Sempre nos blocos `if language == 'ptbr' ... elseif language == 'enus'` da página.
  Não escreva texto fixo no `.otui` para conteúdo traduzível.

### Mudar comportamento de liga/desliga de uma feature
- Localize o `g_minibot.setModuleToggle(<id>, ...)` na página (use a tabela da seção 3)
  e ajuste a condição. Após alterar config que afeta o motor, chamar `g_minibot.cycle()`
  costuma ser necessário para reprocessar.

---

## 11. Referência rápida de funções (em [minibot.lua](minibot.lua))

| Função | Uso |
|---|---|
| `toggle()` / `show()` / `hide()` | Abrir/fechar o painel. |
| `getPressetSettings()` / `setPressetSettings(t)` | Ler/gravar config do **preset atual**. |
| `getSettingsValue(ownPlayer, k, def)` / `setSettingsValue(...)` | Config global (`false`) ou por personagem (`true`). |
| `loadMainPanel(ui)` | Carrega uma página em `pages/`. |
| `selectMinibotPanel(primary, secondary)` | Seleciona aba/sub-aba por `identifier`. |
| `reloadInternalModules()` | Reaplica todas as páginas (após trocar preset). |
| `reloadLanguage()` | Reaplica idioma na janela e na página atual. |
| `onExportCurrentPreset()` / `importNewPreset(recorder)` | Export/import de preset por código. |
| `getVersionStr()` | Versão exibida. |
