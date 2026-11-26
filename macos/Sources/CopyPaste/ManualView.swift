import SwiftUI

/// Text in the three languages; shows the one in use.
private func tr(_ pt: String, _ en: String, _ es: String) -> String {
    switch AppLanguage.current {
    case .en: return en
    case .es: return es
    default: return pt
    }
}

/// One topic of the user manual: what the feature does, how to use it step by step, and tips.
struct ManualTopic: Identifiable, Hashable {
    let id: String
    let symbol: String
    /// Global shortcuts that open this feature (shown as the user configured them).
    let actions: [HotKeyAction]
    let title: String
    let intro: String
    let steps: [String]
    let tips: [String]

    static var all: [ManualTopic] { [
        ManualTopic(
            id: "start", symbol: "sparkles", actions: [],
            title: tr("Primeiros passos", "Getting started", "Primeros pasos"),
            intro: tr("O CopyPaste fica no ícone da barra de menus, no alto da tela. Tudo funciona por atalhos de teclado que valem em qualquer app.",
                      "CopyPaste lives in the menu bar icon at the top of the screen. Everything works through keyboard shortcuts that work in any app.",
                      "CopyPaste vive en el icono de la barra de menús, arriba en la pantalla. Todo funciona con atajos de teclado que sirven en cualquier app."),
            steps: [
                tr("Clique no ícone da barra de menus para ver as funções, os atalhos e as últimas cópias.",
                   "Click the menu bar icon to see the features, shortcuts and your latest copies.",
                   "Haz clic en el icono de la barra de menús para ver las funciones, los atajos y lo último copiado."),
                tr("Conceda as permissões quando o macOS pedir: Acessibilidade (para colar), Gravação de Tela (para capturar e gravar) e Microfone (para o ditado).",
                   "Grant the permissions when macOS asks: Accessibility (to paste), Screen Recording (to capture and record) and Microphone (for dictation).",
                   "Concede los permisos cuando macOS los pida: Accesibilidad (para pegar), Grabación de pantalla (para capturar y grabar) y Micrófono (para el dictado)."),
                tr("Em Configurações você muda qualquer atalho, a pasta onde as capturas são salvas, o idioma e a IA do ditado.",
                   "In Settings you can change any shortcut, the folder where screenshots are saved, the language and the dictation AI.",
                   "En Configuración puedes cambiar cualquier atajo, la carpeta donde se guardan las capturas, el idioma y la IA del dictado."),
            ],
            tips: [
                tr("A seção Permissões em Configurações mostra o que já foi liberado e abre o ajuste certo do macOS.",
                   "The Permissions section in Settings shows what is already allowed and opens the right macOS setting.",
                   "La sección Permisos en Configuración muestra lo que ya está permitido y abre el ajuste correcto de macOS."),
            ]),
        ManualTopic(
            id: "history", symbol: "list.clipboard", actions: [.clipboard],
            title: tr("Histórico de cópias", "Clipboard history", "Historial del portapapeles"),
            intro: tr("Tudo o que você copia (texto, links, imagens, arquivos, cores) fica guardado para colar de novo depois.",
                      "Everything you copy (text, links, images, files, colors) is saved so you can paste it again later.",
                      "Todo lo que copias (texto, enlaces, imágenes, archivos, colores) se guarda para pegarlo de nuevo después."),
            steps: [
                tr("Copie normalmente com ⌘C em qualquer app.", "Copy as usual with ⌘C in any app.", "Copia como siempre con ⌘C en cualquier app."),
                tr("Aperte o atalho do histórico: um painel abre perto do cursor.", "Press the history shortcut: a panel opens near the cursor.", "Pulsa el atajo del historial: se abre un panel cerca del cursor."),
                tr("Digite para buscar, use ↑ ↓ para escolher e ↩ para colar onde está o cursor.", "Type to search, use ↑ ↓ to choose and ↩ to paste where the cursor is.", "Escribe para buscar, usa ↑ ↓ para elegir y ↩ para pegar donde está el cursor."),
            ],
            tips: [
                tr("⌘1 a ⌘9 colam direto o item daquela posição; Espaço mostra uma prévia.", "⌘1 to ⌘9 paste the item in that position; Space shows a preview.", "⌘1 a ⌘9 pegan el elemento de esa posición; Espacio muestra una vista previa."),
                tr("⌘P fixa um item: fixados nunca expiram. ⌘L abre a Biblioteca, com busca e filtros.", "⌘P pins an item: pinned items never expire. ⌘L opens the Library, with search and filters.", "⌘P fija un elemento: los fijados nunca caducan. ⌘L abre la Biblioteca, con búsqueda y filtros."),
                tr("Senhas copiadas de gerenciadores de senha não são guardadas. Use \"Pausar captura\" no menu para não guardar nada por um tempo.", "Passwords copied from password managers are never saved. Use \"Pause capturing\" in the menu to save nothing for a while.", "Las contraseñas copiadas de gestores de contraseñas no se guardan. Usa \"Pausar la captura\" en el menú para no guardar nada por un tiempo."),
            ]),
        ManualTopic(
            id: "capture", symbol: "viewfinder", actions: [.captureArea, .captureScreen],
            title: tr("Captura de tela", "Screenshots", "Capturas de pantalla"),
            intro: tr("Capture uma área, uma janela ou a tela inteira e anote com setas, textos, destaques e desfoque antes de copiar ou salvar.",
                      "Capture an area, a window or the whole screen and annotate it with arrows, text, highlights and blur before copying or saving.",
                      "Captura un área, una ventana o la pantalla completa y anótala con flechas, textos, resaltados y desenfoque antes de copiar o guardar."),
            steps: [
                tr("Aperte o atalho: a tela congela.", "Press the shortcut: the screen freezes.", "Pulsa el atajo: la pantalla se congela."),
                tr("Arraste para escolher uma área, ou passe o mouse sobre uma janela e clique para capturá-la. F ou ↩ pega a tela inteira.", "Drag to choose an area, or hover over a window and click to capture it. F or ↩ takes the whole screen.", "Arrastra para elegir un área, o pasa el ratón sobre una ventana y haz clic para capturarla. F o ↩ toma la pantalla completa."),
                tr("Anote com a barra de ferramentas (P caneta, A seta, T texto, H marca-texto, B desfoque, N passos numerados…).", "Annotate with the toolbar (P pen, A arrow, T text, H highlighter, B blur, N numbered steps…).", "Anota con la barra de herramientas (P lápiz, A flecha, T texto, H resaltador, B desenfoque, N pasos numerados…)."),
                tr("↩ copia, ⌘S salva na pasta, ⇧⌘S salva como. Esc cancela.", "↩ copies, ⌘S saves to the folder, ⇧⌘S saves as. Esc cancels.", "↩ copia, ⌘S guarda en la carpeta, ⇧⌘S guarda como. Esc cancela."),
            ],
            tips: [
                tr("⌘T copia o texto da imagem (OCR), sem internet.", "⌘T copies the text in the image (OCR), offline.", "⌘T copia el texto de la imagen (OCR), sin internet."),
                tr("Nas ações da captura você pode fixar a imagem na tela, abrir no quadro ou gravar vídeo daquela área.", "From the capture actions you can pin the image on screen, open it on the board or record a video of that area.", "Desde las acciones de la captura puedes fijar la imagen en pantalla, abrirla en la pizarra o grabar un video de esa área."),
                tr("Antes de selecionar, C copia a cor do pixel sob o mouse.", "Before selecting, C copies the color of the pixel under the mouse.", "Antes de seleccionar, C copia el color del píxel bajo el ratón."),
            ]),
        ManualTopic(
            id: "board", symbol: "pencil.and.scribble", actions: [.board],
            title: tr("Quadro de apresentação", "Presentation board", "Pizarra de presentación"),
            intro: tr("Desenhe por cima de qualquer coisa na tela durante uma reunião, aula ou gravação, ou use um quadro em branco.",
                      "Draw over anything on screen during a meeting, class or recording, or use a blank whiteboard.",
                      "Dibuja sobre cualquier cosa en la pantalla durante una reunión, clase o grabación, o usa una pizarra en blanco."),
            steps: [
                tr("Aperte o atalho do quadro: a barra de ferramentas aparece.", "Press the board shortcut: the toolbar appears.", "Pulsa el atajo de la pizarra: aparece la barra de herramientas."),
                tr("Desenhe, escreva e adicione formas e componentes. K liga o laser, que some sozinho.", "Draw, write and add shapes and components. K turns on the laser, which fades by itself.", "Dibuja, escribe y añade formas y componentes. K activa el láser, que desaparece solo."),
                tr("G troca o fundo (transparente, branco, quadriculado, escuro, lousa). I deixa você clicar nos apps de baixo sem apagar o desenho.", "G changes the background (transparent, white, grid, dark, chalkboard). I lets you click the apps underneath without erasing the drawing.", "G cambia el fondo (transparente, blanco, cuadriculado, oscuro, pizarra verde). I te deja hacer clic en las apps de abajo sin borrar el dibujo."),
                tr("Use os botões da barra para copiar, salvar ou enviar o desenho. Esc fecha.", "Use the toolbar buttons to copy, save or send the drawing. Esc closes.", "Usa los botones de la barra para copiar, guardar o enviar el dibujo. Esc cierra."),
            ],
            tips: [
                tr("Duplo clique numa forma escreve texto dentro dela. ⌘V cola imagens e textos no quadro.", "Double-click a shape to write text inside it. ⌘V pastes images and text onto the board.", "Doble clic en una forma para escribir dentro de ella. ⌘V pega imágenes y textos en la pizarra."),
                tr("O desenho fica guardado ao fechar, até você apagar.", "The drawing is kept when you close the board, until you erase it.", "El dibujo se guarda al cerrar, hasta que lo borres."),
            ]),
        ManualTopic(
            id: "record", symbol: "record.circle", actions: [.record],
            title: tr("Gravação de tela", "Screen recording", "Grabación de pantalla"),
            intro: tr("Grave uma área ou a tela inteira em vídeo, com microfone e som do Mac se quiser.",
                      "Record an area or the whole screen to video, with microphone and Mac sound if you want.",
                      "Graba un área o la pantalla completa en video, con micrófono y sonido del Mac si quieres."),
            steps: [
                tr("Aperte o atalho de gravação e escolha a área (ou clique numa janela).", "Press the recording shortcut and choose the area (or click a window).", "Pulsa el atajo de grabación y elige el área (o haz clic en una ventana)."),
                tr("Ligue ou desligue Microfone e Áudio do Mac e clique em Gravar.", "Turn Microphone and Mac Audio on or off and click Record.", "Activa o desactiva Micrófono y Audio del Mac y haz clic en Grabar."),
                tr("Para parar, aperte o mesmo atalho ou use o ícone vermelho na barra de menus. O vídeo abre no Finder.", "To stop, press the same shortcut or use the red icon in the menu bar. The video opens in Finder.", "Para detener, pulsa el mismo atajo o usa el icono rojo en la barra de menús. El video se abre en el Finder."),
            ],
            tips: [
                tr("Os desenhos do quadro aparecem no vídeo, ótimo para aulas e tutoriais. A moldura vermelha não aparece.", "Board drawings show up in the video, great for classes and tutorials. The red frame does not.", "Los dibujos de la pizarra aparecen en el video, ideal para clases y tutoriales. El marco rojo no aparece."),
                tr("A gravação precisa do macOS 15 ou mais recente.", "Recording requires macOS 15 or later.", "La grabación requiere macOS 15 o posterior."),
            ]),
        ManualTopic(
            id: "dictate", symbol: "mic.fill", actions: [.dictate],
            title: tr("Ditado por voz", "Voice dictation", "Dictado por voz"),
            intro: tr("Fale em vez de digitar, em qualquer app. O texto sai limpo: sem \"é\", \"hã\", com pontuação e com as suas correções aplicadas.",
                      "Speak instead of typing, in any app. The text comes out clean: no \"um\" or \"uh\", with punctuation and your corrections applied.",
                      "Habla en lugar de escribir, en cualquier app. El texto sale limpio: sin \"eh\" ni muletillas, con puntuación y tus correcciones aplicadas."),
            steps: [
                tr("Clique onde quer escrever (um e-mail, chat, documento).", "Click where you want to write (an email, chat, document).", "Haz clic donde quieres escribir (un correo, chat, documento)."),
                tr("Segure o atalho do ditado e fale. Uma pílula embaixo da tela mostra que está ouvindo.", "Hold the dictation shortcut and speak. A pill at the bottom of the screen shows it is listening.", "Mantén pulsado el atajo del dictado y habla. Una píldora abajo en la pantalla muestra que está escuchando."),
                tr("Solte: o texto aparece no lugar do cursor.", "Let go: the text appears at the cursor.", "Suelta: el texto aparece donde está el cursor."),
            ],
            tips: [
                tr("Também dá para tocar uma vez no atalho, falar à vontade e tocar de novo para terminar. Esc cancela.", "You can also tap the shortcut once, speak freely and tap again to finish. Esc cancels.", "También puedes tocar el atajo una vez, hablar con calma y tocarlo de nuevo para terminar. Esc cancela."),
                tr("Em Configurações › Ditado por voz escolha o estilo (natural, formal, descontraído ou literal) e cadastre nomes e termos que devem sair com a grafia certa.", "In Settings › Voice Dictation choose the style (natural, formal, casual or literal) and add names and terms that must be spelled right.", "En Configuración › Dictado por voz elige el estilo (natural, formal, informal o literal) y añade nombres y términos que deben escribirse bien."),
            ]),
        ManualTopic(
            id: "command", symbol: "wand.and.stars", actions: [.voiceCommand],
            title: tr("Comando de voz", "Voice command", "Comando de voz"),
            intro: tr("Em vez de ditar, você dá uma ordem falada e a IA faz: reescreve, traduz, resume ou escreve um texto novo.",
                      "Instead of dictating, you give a spoken instruction and the AI does it: rewrites, translates, summarizes or writes new text.",
                      "En lugar de dictar, das una orden hablada y la IA la cumple: reescribe, traduce, resume o escribe un texto nuevo."),
            steps: [
                tr("Selecione um texto em qualquer app.", "Select some text in any app.", "Selecciona un texto en cualquier app."),
                tr("Segure o atalho do comando e diga o que fazer: \"deixa mais formal\", \"traduz para o inglês\", \"resume em três tópicos\", \"corrige os erros\".", "Hold the command shortcut and say what to do: \"make it more formal\", \"translate to Spanish\", \"summarize in three bullets\", \"fix the mistakes\".", "Mantén pulsado el atajo del comando y di qué hacer: \"hazlo más formal\", \"tradúcelo al inglés\", \"resúmelo en tres puntos\", \"corrige los errores\"."),
                tr("Solte: o resultado substitui o texto selecionado.", "Let go: the result replaces the selected text.", "Suelta: el resultado reemplaza el texto seleccionado."),
            ],
            tips: [
                tr("Sem nada selecionado, a IA escreve o que você pedir onde está o cursor. Ex.: \"escreve um e-mail recusando a reunião de amanhã\".", "With nothing selected, the AI writes what you ask at the cursor. E.g. \"write an email declining tomorrow's meeting\".", "Sin nada seleccionado, la IA escribe lo que pidas donde está el cursor. Ej.: \"escribe un correo rechazando la reunión de mañana\"."),
                tr("Precisa de uma IA ligada (veja o tópico IA).", "It needs an AI turned on (see the AI topic).", "Necesita una IA activada (ve el tema IA)."),
            ]),
        ManualTopic(
            id: "ai", symbol: "cpu", actions: [],
            title: tr("IA: local ou a sua", "AI: local or your own", "IA: local o la tuya"),
            intro: tr("O ditado e o comando de voz usam uma IA. Você escolhe: a IA local, grátis e sem internet, ou a sua conta de Claude, ChatGPT, Gemini, DeepSeek ou Grok.",
                      "Dictation and voice commands use an AI. You choose: the local AI, free and offline, or your own Claude, ChatGPT, Gemini, DeepSeek or Grok account.",
                      "El dictado y el comando de voz usan una IA. Tú eliges: la IA local, gratis y sin internet, o tu propia cuenta de Claude, ChatGPT, Gemini, DeepSeek o Grok."),
            steps: [
                tr("Abra Configurações › Ditado por voz.", "Open Settings › Voice Dictation.", "Abre Configuración › Dictado por voz."),
                tr("IA local: clique em Baixar (cerca de 4 GB, uma vez só) e depois em Testar para conferir.", "Local AI: click Download (about 4 GB, only once) and then Test to check it.", "IA local: haz clic en Descargar (unos 4 GB, una sola vez) y luego en Probar para comprobarla."),
                tr("Ou conecte a sua chave de API: clique em \"Obter chave\" ao lado da IA, crie a chave no site dela e cole no app.", "Or connect your API key: click \"Get a key\" next to the AI, create the key on its site and paste it in the app.", "O conecta tu clave de API: haz clic en \"Obtener clave\" junto a la IA, crea la clave en su sitio y pégala en la app."),
                tr("Escolha qual IA ajusta o texto e qual transcreve a voz.", "Choose which AI cleans up the text and which one transcribes your voice.", "Elige qué IA ajusta el texto y cuál transcribe la voz."),
            ],
            tips: [
                tr("A chave fica guardada no Porta-chaves do Mac. O CopyPaste não cobra nada: o uso é cobrado na sua conta da IA, normalmente centavos.", "The key is stored in the Mac Keychain. CopyPaste charges nothing: usage is billed to your AI account, usually cents.", "La clave se guarda en el Llavero del Mac. CopyPaste no cobra nada: el uso se cobra en tu cuenta de la IA, normalmente céntimos."),
                tr("Se a IA demorar mais de alguns segundos, o texto é colado sem ajuste, para você não ficar esperando.", "If the AI takes more than a few seconds, the text is pasted without cleanup so you are not left waiting.", "Si la IA tarda más de unos segundos, el texto se pega sin ajustar para que no te quedes esperando."),
            ]),
    ] }
}

struct ManualView: View {
    @State private var selection: String? = "start"
    private let topics = ManualTopic.all

    var body: some View {
        NavigationSplitView {
            List(topics, selection: $selection) { t in
                Label(t.title, systemImage: t.symbol).tag(t.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            if let t = topics.first(where: { $0.id == selection }) {
                ScrollView { TopicView(topic: t).padding(28) }
            }
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct TopicView: View {
    let topic: ManualTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: topic.symbol).font(.system(size: 26)).foregroundStyle(.tint)
                Text(topic.title).font(.title.bold())
            }
            Text(topic.intro).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ForEach(topic.actions) { a in
                HStack {
                    Text(a.label)
                    Spacer()
                    Text(AppSettings.shared.hotKey(for: a)?.display ?? tr("sem atalho: defina em Configurações", "no shortcut: set one in Settings", "sin atajo: defínelo en Configuración"))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Como usar", "How to use", "Cómo usar")).font(.headline)
                ForEach(Array(topic.steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)").font(.callout.bold()).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(.tint))
                        Text(s).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !topic.tips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Dicas", "Tips", "Consejos")).font(.headline)
                    ForEach(topic.tips, id: \.self) { tip in
                        Label { Text(tip).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "lightbulb").foregroundStyle(.yellow) }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 620, alignment: .leading)
    }
}
