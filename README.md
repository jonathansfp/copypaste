<div align="center">

🇧🇷 **Português** · 🇺🇸 [English](README.en.md) · 🇪🇸 [Español](README.es.md)

# 📋 CopyPaste

### 100% gratuito · sem anúncios · sem cadastro · código aberto

Desenvolvido por **Jonathan Felix** · contato: [jonathansfp@gmail.com](mailto:jonathansfp@gmail.com)

**Histórico de cópias, captura de tela com anotações, quadro de apresentação, gravação de tela e ditado por voz com IA.**
**Para macOS, Windows e Linux: leve, rápido, gratuito e sem nada rodando à toa.**

![Gratuito](https://img.shields.io/badge/pre%C3%A7o-100%25%20gratuito-15803d)
![macOS](https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-X11%20%7C%20Wayland-FCC624?logo=linux&logoColor=black)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
![Rust](https://img.shields.io/badge/Rust-Tauri%202-DEA584?logo=rust&logoColor=white)
![Licença](https://img.shields.io/badge/licen%C3%A7a-GPL--3.0-blue)

### 🌐 [Página do projeto](https://jonathansfp.github.io/copypaste/) · ⬇️ [Baixar](#-download) · 💚 [Apoiar com Pix](#-apoie-o-projeto)

<img src="docs/componentes.png" width="820" alt="Formas, componentes e estilos de anotação do CopyPaste">

<sub>Tudo o que você vê acima é desenhado pelo motor vetorial do app: formas, componentes no estilo Excalidraw, traço à mão, setas, passos numerados, desfoque, marca-texto e texto nítido.</sub>

</div>

---

## ⬇️ Download

Baixe só o instalador, sem precisar do código:

| Sistema | Arquivo | |
|---|---|---|
| 🪟 **Windows 10/11** | [**CopyPaste-Windows-Setup.exe**](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Windows-Setup.exe) | Instalador (recomendado) |
| | [CopyPaste-Windows.msi](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Windows.msi) | Para empresas / implantação |
| | [CopyPaste-Windows-Portable.zip](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Windows-Portable.zip) | Portátil, sem instalar |
| 🐧 **Linux** | [**CopyPaste-Linux-x86_64.AppImage**](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Linux-x86_64.AppImage) | Qualquer distro: `chmod +x` e abrir |
| | [CopyPaste-Linux-amd64.deb](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Linux-amd64.deb) | Ubuntu, Debian, Mint, Pop!_OS |
| | [CopyPaste-Linux-x86_64.rpm](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-Linux-x86_64.rpm) | Fedora, openSUSE |
| 🍎 **macOS 14+** | [**CopyPaste-macOS.dmg**](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-macOS.dmg) | Apple Silicon e Intel |
| | [CopyPaste-macOS.zip](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-macOS.zip) | O mesmo app, compactado |

Todas as versões ficam em [**Releases**](https://github.com/jonathansfp/copypaste/releases). Os arquivos são gerados automaticamente pelo GitHub Actions a partir deste código.

> **Primeira vez abrindo?** O app não é assinado por uma loja, então o sistema pede confirmação uma vez:
> **Windows:** "O Windows protegeu o computador" → *Mais informações* → *Executar assim mesmo*.
> **macOS:** botão direito no app → *Abrir* → *Abrir* (ou `xattr -dr com.apple.quarantine /Applications/CopyPaste.app`).
> **Linux (AppImage):** `chmod +x CopyPaste-Linux-x86_64.AppImage && ./CopyPaste-Linux-x86_64.AppImage`.

---

## 💚 Apoie o projeto

O CopyPaste é **gratuito e de código aberto**. Se ele poupa seu tempo, considere uma doação via **Pix**. Qualquer valor ajuda a manter o projeto vivo e com novidades.

<table><tr><td>

**Chave Pix (aleatória)**

```
586cb2d1-8a6e-4bed-8cdb-1f413e8f3e38
```

</td></tr></table>

No app do seu banco: **Pix → Pagar → Chave aleatória** e cole a chave. A opção também está dentro do app: **menu do ícone → Doar via Pix ♥** (copia a chave).

---

## 🗂️ Estrutura do repositório

Cada sistema tem a sua pasta. O Mac usa um app 100% nativo em Swift; Windows e Linux compartilham um núcleo em Rust, com o código específico de cada sistema na sua pasta.

```
copypaste/
├── macos/     🍎 App nativo do Mac (Swift, AppKit + SwiftUI, ScreenCaptureKit) — build.sh, package.sh
├── windows/   🪟 Código nativo do Windows (Rust: colar com SendInput, OCR do Windows, janela fora da gravação) — build.ps1
├── linux/     🐧 Código nativo do Linux (Rust: X11/Wayland, xdotool/wtype, Tesseract, PulseAudio/PipeWire) — build.sh
├── core/      ⚙️ Núcleo compartilhado de Windows e Linux (Tauri 2: Rust + interface em canvas acelerado por GPU)
├── docs/      Página do projeto (GitHub Pages) e imagens do README
└── .github/workflows/release.yml   Gera e publica os instaladores dos três sistemas
```

| | macOS | Windows | Linux |
|---|---|---|---|
| Histórico de cópias com busca e filtros | ✅ | ✅ | ✅ |
| Colar no app anterior (Enter / duplo clique) | ✅ | ✅ | ✅ (X11: xdotool · Wayland: wtype/ydotool) |
| Captura congelada, lupa, destaque de janelas | ✅ | ✅ | ✅ |
| Anotações (setas, formas, texto nítido, passos, desfoque, marca-texto) | ✅ | ✅ | ✅ |
| Fixar captura na tela | ✅ | ✅ | ✅ |
| Copiar texto da imagem (OCR) | ✅ Vision | ✅ OCR do Windows | ✅ Tesseract |
| Quadro de apresentação estilo Excalidraw + laser | ✅ | ✅ | ✅ |
| Gravação de tela MP4 + microfone + áudio do sistema | ✅ | ✅ (ffmpeg) | ✅ (ffmpeg) |
| Ditado por voz com IA local (Gemma 4, offline) ou a sua (Claude, GPT, Gemini, DeepSeek, Grok) | ✅ (+ transcrição da Apple) | ✅ | ✅ |
| Aviso semanal de nova versão | ✅ | ✅ | ✅ |
| Comando de voz sobre o texto selecionado | ✅ | ✅ | ✅ (X11: xdotool · Wayland: wtype/ydotool) |
| Atalhos globais configuráveis | ✅ | ✅ | ✅ (Wayland: atalho do sistema → `copypaste --capture-area`) |

Detalhes de cada sistema: [`macos/`](macos/README.md) · [`windows/`](windows/README.md) · [`linux/`](linux/README.md) · [`core/`](core/README.md).

---

## Sumário

- [Download](#-download)
- [Apoie o projeto](#-apoie-o-projeto)
- [Estrutura do repositório](#️-estrutura-do-repositório)
- [Por que o CopyPaste?](#por-que-o-copypaste)
  - [As dores do Mac que o CopyPaste resolve](#-as-dores-do-mac-que-o-copypaste-resolve)
- [Recursos](#recursos)
  - [Histórico de cópias](#-histórico-de-cópias)
  - [Captura de tela](#-captura-de-tela)
  - [Modo apresentação (quadro)](#-modo-apresentação-quadro)
  - [Gravação de tela](#-gravação-de-tela)
  - [Ditado por voz com IA](#️-ditado-por-voz-com-ia)
- [Atalhos](#atalhos)
- [Windows e Linux](#-windows-e-linux)
- [Instalação no Mac](#instalação-no-mac)
- [Permissões](#permissões)
- [Compilando do código-fonte](#compilando-do-código-fonte)
- [Arquitetura](#arquitetura)
- [Desempenho e memória](#desempenho-e-memória)
- [Privacidade](#privacidade)
- [Solução de problemas](#solução-de-problemas)
- [Licença](#licença)

---

## Por que o CopyPaste?

O Mac é excelente, mas várias tarefas do dia a dia **simplesmente não existem no macOS**, ou exigem três apps diferentes, assinaturas pagas e muitos cliques. O CopyPaste junta tudo isso num app só, **nativo, gratuito, offline e leve**, com qualidade de app profissional.

### 🩹 As dores do Mac que o CopyPaste resolve

| # | A dor no macOS | Como o CopyPaste resolve |
|:-:|---|---|
| 1 | **O Mac só lembra a última coisa copiada.** Copiou outra coisa e a anterior sumiu para sempre. | **Histórico de cópias** com texto, links, código, cores, imagens e arquivos, busca, fixados e colagem direto no cursor (`⇧⌘V`). |
| 2 | **Anotar um print é um ritual:** `⇧⌘4`, esperar a miniatura, abrir a Marcação, editar, salvar, procurar o arquivo. | **Anota no lugar, na hora**: seta, texto, destaque, passos numerados e desfoque direto sobre a seleção, e `↩` copia. Sem janelas extras. |
| 3 | **A Mesa vira um depósito de "Captura de Tela 2026-…png".** | Por padrão, a captura vai **para a área de transferência**. Salvar só quando você quiser, numa pasta própria (`~/Pictures/CopyPaste`), em PNG ou JPG. |
| 4 | **Esconder senhas, e-mails ou dados de clientes** num print exige outro editor. | Ferramenta **Desfocar / ocultar** (`B`), que pixeliza a área em blocos grandes no próprio arquivo final (não é uma camada removível por cima). |
| 5 | **Copiar o texto de uma imagem, de um vídeo ou de um app que não deixa selecionar** é um sofrimento. | **OCR offline em português** (`⌘T`): selecione qualquer área da tela e o texto vai para a área de transferência. |
| 6 | **Descobrir a cor exata de um pixel** exige o escondido "Medidor de Cor Digital". | **Lupa com conta-gotas** na própria captura: `C` copia a cor em hex (`#1E90FF`). |
| 7 | **Precisa de uma referência na tela** (um layout, um trecho de código, uma tabela) enquanto trabalha em outra janela. | **Fixar na tela**: a captura vira uma janelinha flutuante por cima de tudo, com transparência ajustável. |
| 8 | **Não dá para desenhar na tela** durante uma reunião, aula ou gravação para apontar e explicar. | **Modo apresentação**: caneta, setas, laser e componentes por cima de qualquer app, com um modo que deixa os cliques passarem para os apps de baixo. |
| 9 | **Esboçar uma ideia ou um diagrama rápido** exige abrir o navegador ou outro app. | **Quadro instantâneo** (branco, quadriculado, escuro ou lousa) com componentes no estilo Excalidraw: notas, bancos de dados, pessoas, nuvens, janelas, celulares e traço à mão. |
| 10 | **A gravação nativa (`⇧⌘5`) não grava o som do Mac**, só o microfone. Gravar uma aula ou um tutorial com o som do vídeo vira gambiarra. | **Grava tela + microfone + áudio do Mac juntos**, com cliques destacados, por área ou tela inteira, codificado por hardware. |
| 11 | **Atalhos de captura do sistema são fixos e difíceis de lembrar** (`⇧⌘3`, `⇧⌘4`, `⇧⌘4` + `Espaço`, `⇧⌘5`…). | **Todos os atalhos são configuráveis**, inclusive com teclas F sozinhas (como a Print Screen de teclados externos), com aviso de conflito. |
| 12 | **As alternativas são pesadas, lentas ou pagas:** apps em Electron que travam ao abrir, ou assinaturas mensais. | **100% nativo em Swift**, sem dependências, ~50 MB em repouso, abre a captura em ~150 ms. **Gratuito e de código aberto.** |
| 13 | **Gerenciadores de clipboard podem guardar as suas senhas.** | **Ignora automaticamente** o que 1Password, KeeWeb e outros marcam como confidencial. Nada sai do seu Mac. |

### ⚖️ Comparado a ferramentas de captura comuns

Ferramentas como o Lightshot costumam **demorar para abrir**, deixam **texto borrado** e têm poucas ferramentas. Veja a diferença:

| | Ferramentas comuns | **CopyPaste** |
|---|---|---|
| Abrir a captura | Demora e às vezes trava | **A tela congela na hora** (~150 ms com 2 monitores) |
| Nitidez | Anotações rasterizadas | **Vetores** desenhados na resolução Retina |
| Ferramentas | Caneta, seta, retângulo | + marca-texto, passos numerados, desfoque, texto com fundo, **componentes**, traço à mão, laser |
| Janelas | Seleção manual | **Destaca a janela sob o mouse**; um clique captura só ela |
| Precisão | Sem lupa | **Lupa** com coordenadas e cor do pixel (copia o hex) |
| Texto da imagem | — | **OCR** offline, em português |
| Depois da captura | Copiar / salvar | + **fixar na tela**, **abrir no quadro**, **gravar a área**, Google Lens |
| Apresentação | — | **Quadro** sobre a tela ou em fundo branco, quadriculado, escuro ou lousa |
| Vídeo | — | **Gravação** de tela com microfone e áudio do Mac |
| Atalhos | Fixos | **Todos configuráveis**, com aviso de conflito |
| Consumo | Processo sempre ativo | **Nada fica rodando em segundo plano**: tudo é criado sob demanda e liberado ao fechar |

---

## Recursos

### 📋 Histórico de cópias

- Guarda **texto, links, código, cores, imagens e arquivos** copiados, com o ícone do app de onde vieram.
- **Painel rápido** (`⇧⌘V`) que abre junto ao cursor de texto, ao ponteiro do mouse ou no centro da tela.
- **Cola direto** onde está o cursor (com a permissão de Acessibilidade) ou só copia.
- **Biblioteca** completa com busca, filtros por tipo, fixados e mais usados.
- Itens **fixados** nunca expiram. Dá para escolher por quanto tempo guardar (de 1 hora a para sempre) e um limite de itens.
- **Ignora gerenciadores de senha**: conteúdo marcado como confidencial (1Password, KeeWeb etc.) nunca é salvo.
- Reconhece cores (`#FF8800`, `rgb(…)`) e mostra a amostra; detecta código pelo conteúdo e pelo app de origem.

### 📸 Captura de tela

1. Aperte o atalho e **a tela congela imediatamente**, em todos os monitores.
2. **Passe o mouse** sobre uma janela para destacá-la, e **clique** para capturá-la. Ou **arraste** para escolher uma área.
3. Anote, depois **copie** (`↩`), **salve** (`⌘S`) ou escolha outra ação.

**Seleção precisa**
- Lupa com zoom de pixels, coordenadas e cor (`C` copia a cor em hexadecimal).
- Setas do teclado movem o ponteiro 1 pixel por vez.
- `⇧` deixa a seleção quadrada, `F` ou `↩` seleciona a tela inteira.
- Depois de selecionar: alças para redimensionar, `⌘` + arrastar para mover a área (as anotações vão junto).
- O tamanho real em pixels aparece sempre acima da seleção.

**Ferramentas de anotação**

| Ferramenta | Tecla | Ferramenta | Tecla |
|---|:-:|---|:-:|
| Selecionar / mover / redimensionar | `V` | Texto (com ou sem fundo) | `T` |
| Caneta | `P` | Passo numerado ①②③ | `N` |
| Marca-texto | `H` | Desfocar / ocultar dados | `B` |
| Linha | `L` | Borracha | `E` |
| Seta | `A` | Nota adesiva | `S` |
| Retângulo | `R` | Losango | `D` |
| Elipse | `O` | Laser (apresentação) | `K` |

**Estilo:** 12 cores (`1`–`9` trocam rápido), 4 espessuras, preenchimento (nenhum, suave ou sólido), tracejado, **traço desenhado à mão** e 5 fontes (Sistema, Arredondada, Manuscrita, Serifada, Código) com tamanho ajustável.

**Edição:** desfazer e refazer ilimitados, `⌥` + arrastar duplica, `⇧` restringe linhas a 45° e formas a quadrado ou círculo, setas do teclado movem o item selecionado e duplo clique edita o texto.

**Ações após capturar**

| Ação | Atalho |
|---|:-:|
| Copiar | `↩` · `⌘C` · duplo clique |
| Salvar na pasta configurada | `⌘S` |
| Salvar como… | `⇧⌘S` |
| Copiar o texto da imagem (OCR, offline) | `⌘T` |
| Pesquisar a imagem no Google Lens | — |
| **Fixar na tela** (fica por cima das janelas; rolagem ajusta a transparência) | — |
| **Abrir no quadro** de apresentação | — |
| **Gravar vídeo** desta área | — |

### 🎨 Modo apresentação (quadro)

Desenhe **por cima de qualquer coisa na tela** durante uma reunião, aula ou gravação, ou use um quadro em branco.

- **Fundos:** transparente sobre a tela, quadro branco, quadriculado, escuro e lousa verde (`G` alterna).
- **Componentes no estilo Excalidraw:** nota adesiva, banco de dados, pessoa, nuvem, balão de fala, janela de navegador, celular, estrela, certo e errado, seta dupla, além de retângulo, elipse e losango.
- **Texto dentro dos componentes:** duplo clique em qualquer forma para escrever dentro dela, centralizado e com quebra de linha.
- **Laser:** um traço vermelho que some sozinho, para apontar sem sujar o quadro.
- **Modo interagir (`I`):** os cliques passam para os apps de baixo e o desenho continua visível. Volte a desenhar pelo atalho do quadro ou pela pílula no topo da tela.
- **Colar (`⌘V`):** imagens e textos da área de transferência viram itens do quadro.
- **Exportar e enviar:** botões na própria barra para **copiar** (cole direto no WhatsApp, Teams, Slack ou e-mail), **salvar** e, no Mac, **enviar** pelo AirDrop, Mensagens ou Mail (`⇧⌘E`). No menu ⋯ ficam salvar como e fixar na tela. Com fundo transparente, a exportação inclui o que estava na tela, em Retina.
- O desenho **fica guardado** ao fechar o quadro, até você apagar.
- **Barra móvel:** arraste pela alça (☰) para onde quiser. Solte numa lateral e ela fica **vertical**; perto do topo ou da base, horizontal. Ela nunca fica atrás do notch da câmera e lembra a posição (duplo clique na alça volta ao padrão).

### 🎬 Gravação de tela

- Grave uma **área** ou a **tela inteira**. Clique numa janela para gravar só a região dela.
- **Microfone** e **áudio do Mac** (sons dos apps), cada um com seu botão.
- **Destaque dos cliques do mouse**; 24, 30 ou 60 quadros por segundo.
- Codificação por **hardware** (H.264 via ScreenCaptureKit), com pouco uso de CPU.
- Uma moldura vermelha marca a área gravada e **não aparece no vídeo**. Os desenhos do quadro **aparecem**, o que serve para gravar aulas e tutoriais.
- Durante a gravação, o ícone na barra fica vermelho com um cronômetro. Para parar, use o mesmo atalho ou o menu.
- O vídeo é salvo em `~/Movies/CopyPaste` e o Finder abre mostrando o arquivo.

> A gravação requer **macOS 15** ou mais recente. As demais funções rodam a partir do macOS 14.

### 🎙️ Ditado por voz com IA

Fale em vez de digitar, **em qualquer app**: segure o atalho, fale e solte. O texto aparece onde está o cursor, já **sem "é", "hã", "tipo", com pontuação, acentos e listas**, e com as suas autocorreções aplicadas ("às três, não, quer dizer, às quatro" vira "às quatro").

- **Segure e fale** (`⌥Espaço` no Mac, `Ctrl+Shift+Espaço` no Windows e no Linux), ou **toque uma vez** para ficar ouvindo e toque de novo para terminar. `Esc` ou o ✕ cancela.
- **Comando de voz** (`⌥⇧Espaço` / `Ctrl+Alt+Espaço`): selecione um texto e diga o que fazer, como "traduza para inglês", "deixe mais formal" ou "resuma em três tópicos". O resultado substitui a seleção. Sem seleção, a IA escreve o que você pedir.
- **IA local, padrão e grátis:** o **Gemma 4 E2B** do Google roda no seu computador pelo [llama.cpp](https://github.com/ggml-org/llama.cpp), sem internet e sem chave. Ele transcreve a voz e ajusta o texto. É baixado uma vez em **Configurações** (cerca de 4 GB), com versões fixas e conferidas por SHA-256, e libera a memória após 10 minutos sem uso. É a IA usada quando nenhuma outra está ativa.
- **Ou use a sua própria IA.** Conecte a sua chave de API em **Configurações**: **Claude** (Anthropic), **ChatGPT** (OpenAI), **Gemini** (Google), **DeepSeek** ou **Grok** (xAI). Escolha o modelo de cada uma; o app já sugere um rápido (no Gemini, o `gemini-flash-latest`).
- **Transcrição:** IA local (todos os sistemas), **Apple** (Mac, grátis e no próprio computador), **OpenAI** ou **Gemini** (com a sua chave).
- **Estilos:** natural, formal (e-mails), descontraído (chats) ou literal (só a transcrição, sem IA). No Mac, o tom se adapta ao app em uso.
- **Vocabulário:** cadastre nomes, siglas e termos técnicos para saírem com a grafia certa.
- Uma pílula discreta na parte de baixo da tela mostra o nível da voz e o andamento, e **não aparece em capturas nem gravações**.

> 🔑 **Sem servidor e sem mensalidade:** o CopyPaste não cobra nada pela IA. A chave fica no **Porta-chaves** do Mac (no Windows e no Linux, num arquivo só seu na pasta de configurações), e o áudio e o texto vão direto do seu computador para a IA escolhida, cobrados na sua conta dela, normalmente centavos por mês.

---

## Atalhos

### Globais (configuráveis)

Em **Configurações › Atalhos globais**: clique no atalho e pressione a nova combinação. `⌫` desativa e `↺` volta ao padrão. Teclas F sozinhas (F13–F20, como a **Print Screen** de teclados externos) também valem. Se a combinação já pertencer a outra ação, o app avisa e desativa a outra.

| Ação | Padrão |
|---|:-:|
| Abrir histórico de cópias | `⇧⌘V` |
| Capturar área ou janela | `⇧⌘1` |
| Capturar tela inteira | `⇧⌘2` |
| Modo apresentação (quadro) | `⌥⇧⌘D` |
| Gravar tela (iniciar / parar) | `⌥⇧⌘R` |
| Ditado por voz (segure ou toque) | `⌥Espaço` |
| Comando de voz sobre o texto selecionado | `⌥⇧Espaço` |

> 💡 **Vindo do Lightshot?** Defina a captura de área como `F13`, a mesma tecla dele.
> ⚠️ Atalhos globais valem em **todos** os apps. Evite combinações como `⌘G` ou `⌘F`, que tirariam o "Buscar" dos outros programas.

### No painel de histórico

| Tecla | Ação |
|---|---|
| `↑` `↓` | Navegar |
| `↩` ou duplo clique | Colar onde está o cursor |
| `⌘↩` ou `⌘C` | Só copiar |
| `⌘1` … `⌘9` | Colar o item da posição |
| `Espaço` | Pré-visualizar |
| `⇥` / `⇧⇥` | Trocar filtro |
| `⌘P` | Fixar / desafixar |
| `⌘⌫` | Excluir item |
| `⌘L` | Abrir a biblioteca |
| `⎋` | Fechar |

### Na captura e no quadro

| Tecla | Ação |
|---|---|
| `V P H L A R O D T N S B E K` | Ferramentas |
| `1` … `9` | Trocar cor |
| `⌘Z` / `⇧⌘Z` | Desfazer / refazer |
| `⌫` | Apagar o item selecionado |
| `⌘D` · `⌥` + arrastar | Duplicar |
| `⌘A` | Selecionar tudo |
| `⇧` arrastando | 45°, quadrado, círculo |
| `⎋` | Desmarcar · fechar |
| `G` · `I` · `F` (quadro) | Fundo · interagir com a tela · trazer para frente |

---

## 🪟🐧 Windows e Linux

Os mesmos recursos, com a mesma ideia de qualidade: a tela congela no instante do atalho, as anotações são vetores renderizados na **resolução nativa** do monitor (texto e setas nítidos em telas 4K com escala de 150%/200%) e a interface roda num canvas acelerado por GPU.

**Atalhos padrão** (todos configuráveis em *Configurações › Atalhos*):

| Atalho | Ação |
|---|---|
| `Win` `Alt` `V` | Histórico de cópias (no Windows; no Linux, `Ctrl` `Shift` `V`) |
| `PrtSc` | Capturar área ou janela (como o Lightshot) |
| `Shift` `PrtSc` | Capturar a tela inteira |
| `Ctrl` `Shift` `D` | Modo apresentação (quadro) |
| `Ctrl` `Shift` `R` | Gravar a tela (de novo para parar) |
| `Ctrl` `Shift` `Espaço` | Ditado por voz (segure e fale, ou toque) |
| `Ctrl` `Alt` `Espaço` | Comando de voz sobre o texto selecionado |

> **Windows 11:** se o `PrtSc` abrir a Ferramenta de Captura do sistema, desligue em *Configurações › Acessibilidade › Teclado › "Usar a tecla Print Screen para abrir a captura de tela"*, ou escolha outro atalho.

**Extras opcionais:**

| Para | Windows | Linux |
|---|---|---|
| Gravar a tela | `winget install Gyan.FFmpeg` | `sudo apt install ffmpeg` |
| Colar sozinho | (nativo) | `sudo apt install xdotool` (X11) · `wtype` ou `ydotool` (Wayland) |
| OCR | (nativo, OCR do Windows) | `sudo apt install tesseract-ocr tesseract-ocr-por` |
| Áudio do sistema | Ativar "Mixagem estéreo" nas configurações de som | `pulseaudio-utils` (pactl) |

**Wayland (GNOME/KDE):** se um atalho global não responder, crie um atalho do sistema que rode `copypaste --capture-area` (ou `--capture-screen`, `--history`, `--board`, `--record`). O app já aberto recebe o comando na hora.

**Dados:** o histórico e as configurações ficam em `%APPDATA%\io.github.jonathansfp.copypaste` (Windows) ou `~/.local/share/io.github.jonathansfp.copypaste` e `~/.config/io.github.jonathansfp.copypaste` (Linux). Nada sai do seu computador.

**Compilar:** veja [`windows/README.md`](windows/README.md) e [`linux/README.md`](linux/README.md).

---

## Instalação no Mac

### Pelo `.dmg`

1. Baixe o [`CopyPaste-macOS.dmg`](https://github.com/jonathansfp/copypaste/releases/latest/download/CopyPaste-macOS.dmg) ou gere com `cd macos && ./package.sh` (cria `macos/dist/CopyPaste-<versão>.dmg` e um `.zip`).
2. Arraste o **CopyPaste** para **Aplicativos**.
3. Na primeira vez, clique com o botão direito no app, depois em **Abrir** e **Abrir** de novo. Se aparecer "está danificado":
   ```bash
   xattr -dr com.apple.quarantine /Applications/CopyPaste.app
   ```

### Direto do código

```bash
git clone https://github.com/jonathansfp/copypaste.git
cd copypaste/macos
./install.sh   # compila, instala em /Applications e abre
```

O CopyPaste fica **só na barra de menus**, sem ícone no Dock. Na primeira execução ele abre as configurações e passa a iniciar com o Mac.

---

## Permissões

| Permissão | Para quê | Onde liberar |
|---|---|---|
| **Acessibilidade** | Colar automaticamente onde está o cursor | Ajustes › Privacidade e Segurança › Acessibilidade |
| **Gravação de Tela e Áudio do Sistema** | Capturar e gravar a tela | Ajustes › Privacidade e Segurança › Gravação de Tela |
| **Microfone** | Ditado por voz e gravar a sua voz junto com a tela | O macOS pede no primeiro uso |
| **Reconhecimento de Fala** | Transcrição da Apple no próprio Mac (ditado) | O macOS pede no primeiro ditado |

O status de cada permissão aparece em **Configurações**, com botões que levam direto ao lugar certo.

> Depois de liberar a Gravação de Tela, **feche e abra o CopyPaste**: o macOS só aplica a permissão para o app reaberto.

---

## Compilando do código-fonte

**Requisitos:** macOS 14+, Xcode 15+ (as macros do SwiftUI precisam do Xcode completo, não só das Command Line Tools).

```bash
cd macos
./build.sh     # gera build/CopyPaste.app (universal: Apple Silicon + Intel)
./install.sh   # compila, instala em /Applications e abre
./package.sh   # gera dist/CopyPaste-<versão>.dmg e .zip
```

O `build.sh` usa o Xcode mesmo que o `xcode-select` aponte para as Command Line Tools.

### Assinatura (importante para as permissões)

O macOS prende as permissões de privacidade à **assinatura** do app:

- Com um certificado **Apple Development** ou **Developer ID** no Keychain (o Xcode cria um ao entrar com sua conta Apple), o `build.sh` assina com ele automaticamente. Assim **as permissões continuam valendo depois de recompilar**.
- Sem certificado, o app é assinado só localmente ("ad-hoc"), e o macOS **pede as permissões de novo a cada compilação**.
- Para escolher a identidade: `SIGN_IDENTITY="Developer ID Application: …" ./build.sh`.

### Autoteste de desenho

```bash
macos/build/CopyPaste.app/Contents/MacOS/CopyPaste --selftest /tmp/teste.png
```

Desenha todas as formas e estilos num PNG e confere a detecção de cliques e o desfazer/refazer. A imagem no topo deste README é gerada assim.

---

## Arquitetura

**Mac:** app 100% nativo em **Swift**, com **AppKit + SwiftUI**, sem dependências externas. Usa só frameworks do sistema:
**ScreenCaptureKit** (captura e gravação), **CoreGraphics / CoreImage** (desenho e desfoque), **Vision** (OCR), **Carbon** (atalhos globais, sem precisar de Acessibilidade) e **ServiceManagement** (iniciar com o Mac).

```
macos/Sources/CopyPaste/
├── main.swift, AppDelegate.swift      # Ciclo de vida, menu da barra, janelas
├── HotKeyManager.swift                # Atalhos globais (Carbon) por ação
├── Settings.swift, SettingsView.swift # Preferências e tela de configurações
├── ClipboardStore.swift, ClipItem.swift, QuickPanel.swift, LibraryView.swift, PasteService.swift
│                                      # Histórico de cópias, painel rápido, biblioteca, colar
├── Canvas/                            # Motor de desenho vetorial (captura + quadro)
│   ├── Shapes.swift                   #   Formas, estilos, renderização, traço à mão
│   ├── CanvasModel.swift              #   Estado, seleção, desfazer/refazer
│   ├── CanvasView.swift               #   Interação: criar, mover, redimensionar, editar texto, laser
│   └── CanvasUI.swift                 #   Barras de ferramentas e painel de estilo (SwiftUI)
├── Capture/                           # Captura de tela
│   ├── ScreenGrabber.swift            #   Congelamento via ScreenCaptureKit, janelas, exportação
│   ├── CaptureController.swift        #   Seleção, lupa, alças, barras, renderização final
│   └── CaptureExtras.swift            #   Aviso rápido (toast), OCR, janela fixada
├── Board/BoardController.swift        # Modo apresentação / quadro
├── Recording/ScreenRecorder.swift     # Gravação de tela + áudio
├── Diag.swift                         # Log de diagnóstico e --diagnose
└── SelfTest.swift                     # --selftest
```

**Windows e Linux:** núcleo em **Rust** com **Tauri 2** (janelas leves usando o WebView do sistema, sem Electron). A captura usa a biblioteca `xcap` (DXGI no Windows; X11/PipeWire no Linux), a área de transferência usa `arboard` e os atalhos globais usam `global-hotkey`. O desenho é o mesmo motor vetorial do Mac, portado para um canvas acelerado por GPU. Veja [`core/README.md`](core/README.md).

**Como a captura funciona (Mac)**
1. O atalho dispara o `CaptureController`, que pede ao ScreenCaptureKit uma imagem de cada monitor, em resolução Retina e sem cursor.
2. Cada monitor ganha uma janela sem bordas que mostra a imagem congelada numa camada da GPU. Por cima dela fica o `CaptureCanvasView`, que desenha o escurecimento, a seleção e as anotações.
3. As anotações são **vetores** (`Shape`). Ao copiar ou salvar, o recorte da imagem original é combinado com as formas desenhadas na resolução real dos pixels, por isso o texto e as setas ficam perfeitamente nítidos.
4. Ao fechar, janelas, imagens e o modelo são liberados.

---

## Desempenho e memória

- **Em repouso:** ~50 MB. Só o monitor da área de transferência roda, uma checagem leve a cada 0,4 s.
- **Captura:** abre em ~150 ms com 2 monitores Retina. A memória sobe enquanto ela está aberta (as telas ficam em resolução total) e é devolvida ao fechar, sem vazamento em capturas repetidas.
- **Desenho:** só as formas são redesenhadas a cada movimento; a imagem congelada fica numa camada da GPU.
- **Gravação:** codificação por hardware, sem cópia de quadros pelo app.

---

## Privacidade

- **Nada sai do seu Mac.** Não há telemetria nem conta. O OCR roda localmente pelo Vision.
- **Atualizações:** uma vez por semana o app consulta a página de versões do GitHub; se houver uma nova, pergunta se você quer atualizar. Com o seu **Atualizar agora**, o app baixa a nova versão, se instala e abre de novo sozinho (no Linux, na versão AppImage; .deb e .rpm abrem a página de download). Nada é enviado além da consulta.
- **Ditado por voz:** com a IA local ou a transcrição da Apple, tudo fica no computador. Ao conectar uma IA, só o áudio do ditado e o texto vão, direto do seu Mac, para o provedor que **você** escolheu, com a **sua** chave. Não há servidor do CopyPaste no meio.
- O histórico fica em `~/Library/Application Support/CopyPaste/`.
- Conteúdo marcado como confidencial por gerenciadores de senha **nunca é salvo**.
- A única ação que abre algo na internet é **Pesquisar no Google Lens**, e só quando você clica: ela abre o navegador e a imagem fica copiada para você colar.

---

## Solução de problemas

<details>
<summary><b>O atalho de captura não faz nada ou o app fica pedindo "Abrir Ajustes"</b></summary>

Quase sempre é a permissão de **Gravação de Tela** presa a uma assinatura antiga do app (aparece ligada em Ajustes, mas o macOS nega). Para resolver:

```bash
tccutil reset ScreenCapture local.copypaste.app
tccutil reset AudioCapture local.copypaste.app
```

Depois feche e abra o CopyPaste, aperte o atalho, libere quando o macOS pedir e clique em **Sair e Reabrir**. Para isso não voltar a acontecer, compile com um certificado estável (veja [Assinatura](#assinatura-importante-para-as-permissões)).
</details>

<details>
<summary><b>O atalho aparece em vermelho ("já é usado por outro app")</b></summary>

Outro programa registrou a mesma combinação (por exemplo, o Lightshot com `F13`). Feche o outro app ou escolha outra combinação em Configurações.
</details>

<details>
<summary><b>Não cola sozinho, só copia</b></summary>

Libere o CopyPaste em **Ajustes › Privacidade e Segurança › Acessibilidade**.
</details>

<details>
<summary><b>Como ver o que está acontecendo por dentro?</b></summary>

O app mantém um log curto (até ~200 KB) em:

```
~/Library/Application Support/CopyPaste/diagnostico.log
```

Ele registra os atalhos (se foram registrados e quando dispararam), o estado das permissões e os erros de captura ou gravação. Para testar só a permissão e a captura:

```bash
open -n /Applications/CopyPaste.app --args --diagnose
# e para salvar também uma imagem da tela principal:
open -n /Applications/CopyPaste.app --args --diagnose --save /tmp/tela.png
```
</details>

---

## Licença

Distribuído sob a licença **GNU GPL v3.0**. Veja [`LICENSE`](LICENSE).

<div align="center"><sub>Feito com Swift e Rust, para quem copia, captura e explica coisas o dia inteiro. 💚 Pix: <code>586cb2d1-8a6e-4bed-8cdb-1f413e8f3e38</code></sub></div>
