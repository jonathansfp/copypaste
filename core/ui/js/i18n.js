// Tradução da interface: o texto em português é a chave; cada entrada traz [inglês, espanhol].
// O idioma vem do app (Configurações › Início › Idioma do app), com o do navegador como reserva.
// t('Texto com {0}', valor) traduz e preenche; translatePage() traduz o HTML estático da página.

const D = {
  // ── configurações: abas e atalhos ──
  'Início': ['Home', 'Inicio'],
  'Atalhos': ['Shortcuts', 'Atajos'],
  'Captura': ['Capture', 'Captura'],
  'Gravação': ['Recording', 'Grabación'],
  'IA e ditado': ['AI and dictation', 'IA y dictado'],
  'Histórico': ['History', 'Historial'],
  'Sobre e apoio': ['About and support', 'Acerca de y apoyo'],
  'Abrir o histórico de cópias': ['Open the clipboard history', 'Abrir el historial del portapapeles'],
  'Capturar área ou janela': ['Capture area or window', 'Capturar área o ventana'],
  'Capturar a tela inteira': ['Capture the full screen', 'Capturar la pantalla completa'],
  'Modo apresentação (quadro)': ['Presentation mode (board)', 'Modo presentación (pizarra)'],
  'Gravar a tela (de novo para parar)': ['Record the screen (again to stop)', 'Grabar la pantalla (otra vez para detener)'],
  'Ditado por voz (segure e fale, ou toque)': ['Voice dictation (hold and speak, or tap)', 'Dictado por voz (mantén pulsado y habla, o toca)'],
  'Comando de voz sobre o texto selecionado': ['Voice command on the selected text', 'Comando de voz sobre el texto seleccionado'],
  'Como usar': ['How to use', 'Cómo usar'],
  'Dicas': ['Tips', 'Consejos'],
  'sem atalho: defina em Configurações › Atalhos': ['no shortcut: set one in Settings › Shortcuts', 'sin atajo: defínelo en Configuración › Atajos'],
  'Desativado': ['Off', 'Desactivado'],
  'desativado': ['off', 'desactivado'],

  // ── configurações: início ──
  'Bem-vindo ao CopyPaste': ['Welcome to CopyPaste', 'Te damos la bienvenida a CopyPaste'],
  'Ele fica perto do relógio (na bandeja do sistema) e não atrapalha nada. Use pelos atalhos:': ['It sits next to the clock (in the system tray) and stays out of the way. Use it with the shortcuts:', 'Se queda junto al reloj (en la bandeja del sistema) y no estorba. Úsalo con los atajos:'],
  'Ele fica perto do relógio (no painel) e não atrapalha nada. Use pelos atalhos:': ['It sits next to the clock (in the panel) and stays out of the way. Use it with the shortcuts:', 'Se queda junto al reloj (en el panel) y no estorba. Úsalo con los atajos:'],
  'Histórico de cópias': ['Clipboard history', 'Historial del portapapeles'],
  '{0} abre tudo o que você copiou: textos, links, imagens, cores e código, com busca. Enter cola no app em que você estava.': ['{0} opens everything you copied: text, links, images, colors and code, with search. Enter pastes into the app you were in.', '{0} abre todo lo que copiaste: textos, enlaces, imágenes, colores y código, con búsqueda. Enter pega en la app en la que estabas.'],
  'Captura com anotações': ['Screenshots with annotations', 'Capturas con anotaciones'],
  '{0} congela a tela na hora: selecione uma área ou janela, anote com setas, texto, desfoque e números, e copie com Enter.': ['{0} freezes the screen instantly: select an area or window, annotate with arrows, text, blur and numbers, and copy with Enter.', '{0} congela la pantalla al instante: selecciona un área o ventana, anota con flechas, texto, desenfoque y números, y copia con Enter.'],
  'Modo apresentação': ['Presentation mode', 'Modo presentación'],
  '{0} desenha por cima da tela ou num quadro branco, com formas no estilo Excalidraw, notas adesivas e laser.': ['{0} draws over the screen or on a whiteboard, with Excalidraw-style shapes, sticky notes and a laser.', '{0} dibuja sobre la pantalla o en una pizarra blanca, con formas al estilo Excalidraw, notas adhesivas y láser.'],
  'Gravação de tela': ['Screen recording', 'Grabación de pantalla'],
  '{0} grava uma área ou a tela inteira em MP4, com microfone e áudio do sistema. O mesmo atalho para.': ['{0} records an area or the full screen to MP4, with microphone and system audio. The same shortcut stops it.', '{0} graba un área o la pantalla completa en MP4, con micrófono y audio del sistema. El mismo atajo la detiene.'],
  'Ditado por voz com IA': ['Voice dictation with AI', 'Dictado por voz con IA'],
  'Segure {0} e fale: o texto aparece onde está o cursor, limpo e pontuado pela IA que você conectar (Claude, GPT, Gemini, DeepSeek ou Grok).': ['Hold {0} and speak: the text appears at the cursor, cleaned up and punctuated by the AI you connect (Claude, GPT, Gemini, DeepSeek or Grok).', 'Mantén pulsado {0} y habla: el texto aparece donde está el cursor, limpio y puntuado por la IA que conectes (Claude, GPT, Gemini, DeepSeek o Grok).'],
  'Idioma do app': ['App language', 'Idioma de la app'],
  'Menus, avisos e janelas do CopyPaste': ['CopyPaste menus, notices and windows', 'Menús, avisos y ventanas de CopyPaste'],
  'Automático (idioma do sistema)': ['Automatic (system language)', 'Automático (idioma del sistema)'],
  'Tudo pronto. Dica: clique com o botão direito no ícone perto do relógio para ver o menu.': ['All set. Tip: right-click the icon next to the clock to see the menu.', 'Todo listo. Consejo: haz clic derecho en el icono junto al reloj para ver el menú.'],

  // ── configurações: atalhos ──
  'Atalhos globais': ['Global shortcuts', 'Atajos globales'],
  'Clique num atalho e pressione a nova combinação. <kbd>Esc</kbd> cancela, <kbd>Backspace</kbd> desativa.': ['Click a shortcut and press the new combination. <kbd>Esc</kbd> cancels, <kbd>Backspace</kbd> turns it off.', 'Haz clic en un atajo y pulsa la nueva combinación. <kbd>Esc</kbd> cancela, <kbd>Backspace</kbd> lo desactiva.'],
  'Voltar ao padrão ({0})': ['Reset to default ({0})', 'Restablecer ({0})'],
  'Padrão': ['Default', 'Predeterminado'],
  'Dentro da captura e do quadro': ['Inside the capture and the board', 'Dentro de la captura y la pizarra'],
  'Ação principal (copiar, salvar ou ambos)': ['Main action (copy, save or both)', 'Acción principal (copiar, guardar o ambas)'],
  'Copiar · salvar na pasta · salvar como': ['Copy · save to folder · save as', 'Copiar · guardar en la carpeta · guardar como'],
  'Fixar na tela · copiar o texto (OCR)': ['Pin to screen · copy the text (OCR)', 'Fijar en pantalla · copiar el texto (OCR)'],
  'Selecionar, caneta, marca-texto, linha, seta, retângulo, elipse, losango, texto, número, nota, desfoque, borracha, laser': ['Select, pen, highlighter, line, arrow, rectangle, ellipse, diamond, text, number, note, blur, eraser, laser', 'Seleccionar, lápiz, resaltador, línea, flecha, rectángulo, elipse, rombo, texto, número, nota, desenfoque, borrador, láser'],
  'Trocar a cor': ['Change the color', 'Cambiar el color'],
  '<kbd>Shift</kbd> arrastando': ['<kbd>Shift</kbd> while dragging', '<kbd>Shift</kbd> al arrastrar'],
  'Retas a 45°, quadrados e círculos perfeitos': ['45° lines, perfect squares and circles', 'Líneas a 45°, cuadrados y círculos perfectos'],
  '<kbd>Ctrl</kbd> arrastando': ['<kbd>Ctrl</kbd> while dragging', '<kbd>Ctrl</kbd> al arrastrar'],
  'Mover a área selecionada': ['Move the selected area', 'Mover el área seleccionada'],
  'Desfazer · refazer': ['Undo · redo', 'Deshacer · rehacer'],
  '<kbd>C</kbd> (antes de selecionar)': ['<kbd>C</kbd> (before selecting)', '<kbd>C</kbd> (antes de seleccionar)'],
  'Copiar a cor do pixel': ['Copy the pixel color', 'Copiar el color del píxel'],
  '<kbd>G</kbd> · <kbd>Ctrl</kbd>+<kbd>V</kbd> (no quadro)': ['<kbd>G</kbd> · <kbd>Ctrl</kbd>+<kbd>V</kbd> (on the board)', '<kbd>G</kbd> · <kbd>Ctrl</kbd>+<kbd>V</kbd> (en la pizarra)'],
  'Trocar o fundo · colar imagem ou texto': ['Change the background · paste an image or text', 'Cambiar el fondo · pegar imagen o texto'],
  'Pressione o atalho…': ['Press the shortcut…', 'Pulsa el atajo…'],
  'Use Ctrl, Alt, Shift ou Win junto': ['Use Ctrl, Alt, Shift or Win with it', 'Usa Ctrl, Alt, Shift o Win junto'],

  // ── configurações: captura e gravação ──
  'Captura de tela': ['Screenshots', 'Captura de pantalla'],
  'A tela congela no instante do atalho: nada some enquanto você seleciona.': ['The screen freezes the moment you press the shortcut: nothing disappears while you select.', 'La pantalla se congela en el instante del atajo: nada desaparece mientras seleccionas.'],
  'Pasta das capturas': ['Screenshots folder', 'Carpeta de capturas'],
  'Escolher…': ['Choose…', 'Elegir…'],
  'Formato ao salvar': ['Format when saving', 'Formato al guardar'],
  'PNG (sem perdas)': ['PNG (lossless)', 'PNG (sin pérdidas)'],
  'JPEG (menor)': ['JPEG (smaller)', 'JPEG (más pequeño)'],
  'Enter faz': ['Enter does', 'Enter hace'],
  'Copiar': ['Copy', 'Copiar'],
  'Salvar na pasta': ['Save to folder', 'Guardar en la carpeta'],
  'Copiar e salvar': ['Copy and save', 'Copiar y guardar'],
  'Lupa com coordenadas e cor': ['Magnifier with coordinates and color', 'Lupa con coordenadas y color'],
  'Ajuda a selecionar no pixel exato': ['Helps you select the exact pixel', 'Ayuda a seleccionar el píxel exacto'],
  'Destacar janelas ao passar o mouse': ['Highlight windows on hover', 'Resaltar ventanas al pasar el ratón'],
  'Clique para capturar a janela inteira': ['Click to capture the whole window', 'Haz clic para capturar la ventana completa'],
  'Vídeo MP4 (H.264 + AAC), que abre em qualquer lugar.': ['MP4 video (H.264 + AAC) that opens anywhere.', 'Video MP4 (H.264 + AAC), que se abre en cualquier lugar.'],
  'Pasta das gravações': ['Recordings folder', 'Carpeta de grabaciones'],
  'Quadros por segundo': ['Frames per second', 'Fotogramas por segundo'],
  'Gravar o microfone': ['Record the microphone', 'Grabar el micrófono'],
  'Gravar o áudio do sistema': ['Record system audio', 'Grabar el audio del sistema'],
  'ffmpeg encontrado: a gravação está pronta.': ['ffmpeg found: recording is ready.', 'ffmpeg encontrado: la grabación está lista.'],
  'Para gravar, instale o ffmpeg (grátis): {0} e reabra esta tela.': ['To record, install ffmpeg (free): {0} and reopen this window.', 'Para grabar, instala ffmpeg (gratis): {0} y vuelve a abrir esta ventana.'],

  // ── configurações: IA e ditado ──
  'IA e ditado por voz': ['AI and voice dictation', 'IA y dictado por voz'],
  'Segure {0} e fale; solte para o texto aparecer onde está o cursor, em qualquer app. Um toque rápido deixa ouvindo até o próximo toque. Com um texto selecionado, {1} aplica o que você pedir ("traduza para inglês", "deixe mais formal").': ['Hold {0} and speak; release it and the text appears at the cursor, in any app. A quick tap keeps listening until the next tap. With text selected, {1} applies whatever you ask ("translate to Spanish", "make it more formal").', 'Mantén pulsado {0} y habla; suéltalo y el texto aparece donde está el cursor, en cualquier app. Un toque rápido deja escuchando hasta el siguiente toque. Con un texto seleccionado, {1} aplica lo que pidas ("traduce al inglés", "hazlo más formal").'],
  'Transcrição da voz': ['Voice transcription', 'Transcripción de la voz'],
  'A IA local roda no computador, sem internet e sem chave': ['The local AI runs on this computer, with no internet and no key', 'La IA local funciona en el equipo, sin internet y sin clave'],
  'IA local Gemma 4 (grátis, offline)': ['Gemma 4 local AI (free, offline)', 'IA local Gemma 4 (gratis, sin conexión)'],
  'OpenAI (sua chave)': ['OpenAI (your key)', 'OpenAI (tu clave)'],
  'Gemini (sua chave)': ['Gemini (your key)', 'Gemini (tu clave)'],
  'Idioma falado': ['Spoken language', 'Idioma hablado'],
  'Português (Brasil)': ['Portuguese (Brazil)', 'Portugués (Brasil)'],
  'Português (Portugal)': ['Portuguese (Portugal)', 'Portugués (Portugal)'],
  'Inglês (EUA)': ['English (US)', 'Inglés (EE. UU.)'],
  'Inglês (Reino Unido)': ['English (UK)', 'Inglés (Reino Unido)'],
  'Espanhol': ['Spanish', 'Español'],
  'Francês': ['French', 'Francés'],
  'Italiano': ['Italian', 'Italiano'],
  'Alemão': ['German', 'Alemán'],
  'Detectar automaticamente': ['Detect automatically', 'Detectar automáticamente'],
  'IA que ajusta o texto': ['AI that polishes the text', 'IA que ajusta el texto'],
  'Tira vícios de fala, pontua e formata': ['Removes filler words, punctuates and formats', 'Quita muletillas, puntúa y da formato'],
  'Estilo': ['Style', 'Estilo'],
  'Natural: limpo, com o seu jeito de falar': ['Natural: clean, in your own way of speaking', 'Natural: limpio, con tu forma de hablar'],
  'Formal: e-mails e documentos': ['Formal: emails and documents', 'Formal: correos y documentos'],
  'Descontraído: chats e mensagens': ['Casual: chats and messages', 'Informal: chats y mensajes'],
  'Literal: só a transcrição, sem IA': ['Literal: just the transcription, no AI', 'Literal: solo la transcripción, sin IA'],
  'Vocabulário': ['Vocabulary', 'Vocabulario'],
  'Nomes, siglas e termos, separados por vírgula': ['Names, acronyms and terms, separated by commas', 'Nombres, siglas y términos, separados por comas'],
  'Ex.: CopyPaste, Kubernetes, Dra. Ana Souza': ['E.g.: CopyPaste, Kubernetes, Dr. Ana Smith', 'Ej.: CopyPaste, Kubernetes, Dra. Ana García'],
  'IA local (padrão, grátis e offline)': ['Local AI (default, free and offline)', 'IA local (predeterminada, gratis y sin conexión)'],
  'O modelo do Google roda no seu computador pelo llama.cpp: transcreve e ajusta o texto sem internet e sem chave. É usado quando nenhuma outra IA está ativa.': ['Google\'s model runs on your computer through llama.cpp: it transcribes and polishes the text with no internet and no key. It is used when no other AI is active.', 'El modelo de Google funciona en tu equipo con llama.cpp: transcribe y ajusta el texto sin internet y sin clave. Se usa cuando no hay otra IA activa.'],
  'Conexões de IA': ['AI connections', 'Conexiones de IA'],
  'Use a sua própria chave de API: o CopyPaste não tem servidor e não cobra nada. A chave fica só neste computador, e o áudio e o texto vão direto para a IA escolhida, cobrados na sua conta dela.': ['Use your own API key: CopyPaste has no server and charges nothing. The key stays on this computer, and the audio and text go straight to the AI you chose, billed to your account there.', 'Usa tu propia clave de API: CopyPaste no tiene servidor y no cobra nada. La clave se queda solo en este equipo, y el audio y el texto van directo a la IA elegida, cobrados en tu cuenta.'],
  'Pronta · {0}': ['Ready · {0}', 'Lista · {0}'],
  'Remover': ['Remove', 'Quitar'],
  'Remover a IA local e liberar o espaço em disco?': ['Remove the local AI and free up the disk space?', '¿Quitar la IA local y liberar el espacio en disco?'],
  'Cancelar': ['Cancel', 'Cancelar'],
  'Instalar (≈ 25 MB)': ['Install (≈ 25 MB)', 'Instalar (≈ 25 MB)'],
  'Baixar (≈ {0})': ['Download (≈ {0})', 'Descargar (≈ {0})'],
  'Nenhuma (texto como foi transcrito)': ['None (text as transcribed)', 'Ninguna (texto tal como se transcribió)'],
  'IA local Gemma 4': ['Gemma 4 local AI', 'IA local Gemma 4'],
  'IA local Gemma 4 (baixar abaixo)': ['Gemma 4 local AI (download below)', 'IA local Gemma 4 (descárgala abajo)'],
  'Texto e voz': ['Text and voice', 'Texto y voz'],
  'Texto': ['Text', 'Texto'],
  'Conectado · {0}': ['Connected · {0}', 'Conectado · {0}'],
  'Modelo de texto': ['Text model', 'Modelo de texto'],
  'Modelo de transcrição': ['Transcription model', 'Modelo de transcripción'],
  'obter chave': ['get a key', 'obtener clave'],
  'Conectar': ['Connect', 'Conectar'],
  'Verificando…': ['Checking…', 'Verificando…'],

  // ── configurações: histórico e sobre ──
  'Fica só no seu computador. Nada é enviado para a internet.': ['It stays on your computer only. Nothing is sent to the internet.', 'Se queda solo en tu equipo. No se envía nada a internet.'],
  'Enter e duplo clique colam no app anterior': ['Enter and double-click paste into the previous app', 'Enter y doble clic pegan en la app anterior'],
  'Desligado: só copiam (você cola com Ctrl+V)': ['Off: they only copy (you paste with Ctrl+V)', 'Desactivado: solo copian (pegas con Ctrl+V)'],
  'Itens guardados (os fixados não contam)': ['Items kept (pinned ones don\'t count)', 'Elementos guardados (los fijados no cuentan)'],
  'Pausar o histórico': ['Pause the history', 'Pausar el historial'],
  'Útil ao copiar senhas': ['Useful when copying passwords', 'Útil al copiar contraseñas'],
  'Iniciar com o sistema': ['Start with the system', 'Iniciar con el sistema'],
  'Apagar o histórico': ['Clear the history', 'Borrar el historial'],
  'Suporte': ['Support', 'Soporte'],
  'Privacidade e termos de uso': ['Privacy & terms of use', 'Privacidad y términos de uso'],
  'Apagar (mantém os fixados)': ['Clear (keeps pinned items)', 'Borrar (conserva los fijados)'],
  'Apagar todo o histórico (exceto os fixados)?': ['Clear the whole history (except pinned items)?', '¿Borrar todo el historial (excepto los fijados)?'],
  'CopyPaste {0} para {1} · código aberto (GPL-3.0)': ['CopyPaste {0} for {1} · open source (GPL-3.0)', 'CopyPaste {0} para {1} · código abierto (GPL-3.0)'],
  'O CopyPaste é gratuito. Se ele poupa seu tempo, considere uma doação via <b>Pix</b> — qualquer valor ajuda a manter o projeto vivo e com novidades.': ['CopyPaste is free. If it saves you time, consider a donation via <b>Pix</b> (Brazil\'s instant payment system) — any amount helps keep the project alive and growing.', 'CopyPaste es gratuito. Si te ahorra tiempo, considera una donación vía <b>Pix</b> (el sistema de pago instantáneo de Brasil): cualquier monto ayuda a mantener el proyecto vivo y con novedades.'],
  'Copiar chave Pix': ['Copy Pix key', 'Copiar clave Pix'],
  'No app do seu banco: Pix → Pagar → Chave aleatória → cole a chave.': ['In your bank\'s app: Pix → Pay → Random key → paste the key.', 'En la app de tu banco: Pix → Pagar → Clave aleatoria → pega la clave.'],
  'Código, novidades e downloads:': ['Code, news and downloads:', 'Código, novedades y descargas:'],
  'Chave Pix copiada — obrigado! ♥': ['Pix key copied — thank you! ♥', 'Clave Pix copiada — ¡gracias! ♥'],
  'por Jonathan Felix': ['by Jonathan Felix', 'por Jonathan Felix'],

  // ── títulos das janelas ──
  'CopyPaste — Configurações': ['CopyPaste — Settings', 'CopyPaste — Configuración'],
  'CopyPaste — captura': ['CopyPaste — capture', 'CopyPaste — captura'],
  'CopyPaste — imagem fixada': ['CopyPaste — pinned image', 'CopyPaste — imagen fijada'],
  'Configurações': ['Settings', 'Configuración'],

  // ── histórico ──
  'Tudo': ['All', 'Todo'],
  'Fixados': ['Pinned', 'Fijados'],
  'Links': ['Links', 'Enlaces'],
  'Imagens': ['Images', 'Imágenes'],
  'Cores': ['Colors', 'Colores'],
  'Código': ['Code', 'Código'],
  'Buscar no histórico…': ['Search the history…', 'Buscar en el historial…'],
  'agora': ['just now', 'ahora'],
  'há {0} min': ['{0} min ago', 'hace {0} min'],
  'há {0} h': ['{0} h ago', 'hace {0} h'],
  'ontem': ['yesterday', 'ayer'],
  'há {0} dias': ['{0} days ago', 'hace {0} días'],
  'Nada encontrado.': ['Nothing found.', 'No se encontró nada.'],
  'Copie algo (Ctrl+C) e ele aparece aqui.': ['Copy something (Ctrl+C) and it shows up here.', 'Copia algo (Ctrl+C) y aparecerá aquí.'],
  'Imagem': ['Image', 'Imagen'],
  '{0} caracteres': ['{0} characters', '{0} caracteres'],
  'usado {0}×': ['used {0}×', 'usado {0}×'],
  'Fixado': ['Pinned', 'Fijado'],
  '{0} de {1}': ['{0} of {1}', '{0} de {1}'],
  'colar': ['paste', 'pegar'],
  'só copiar': ['copy only', 'solo copiar'],
  'Espaço': ['Space', 'Espacio'],
  'ver': ['view', 'ver'],
  'fixar': ['pin', 'fijar'],
  'excluir': ['delete', 'eliminar'],

  // ── captura e quadro ──
  'Selecionar e mover': ['Select and move', 'Seleccionar y mover'],
  'Borracha': ['Eraser', 'Borrador'],
  'Laser (apresentação)': ['Laser (presentation)', 'Láser (presentación)'],
  'Tela congelada': ['Frozen screen', 'Pantalla congelada'],
  'Quadro branco': ['Whiteboard', 'Pizarra blanca'],
  'Papel quadriculado': ['Grid paper', 'Papel cuadriculado'],
  'Quadro escuro': ['Dark board', 'Pizarra oscura'],
  'Lousa verde': ['Green chalkboard', 'Pizarra verde'],
  'Cor e estilo (1–9 trocam a cor)': ['Color and style (1–9 change the color)', 'Color y estilo (1–9 cambian el color)'],
  'Arraste para mover a barra · duplo clique volta ao padrão': ['Drag to move the bar · double-click to reset', 'Arrastra para mover la barra · doble clic la restablece'],
  'Biblioteca de componentes': ['Shape library', 'Biblioteca de formas'],
  'Desfazer (Ctrl+Z)': ['Undo (Ctrl+Z)', 'Deshacer (Ctrl+Z)'],
  'Refazer (Ctrl+Shift+Z)': ['Redo (Ctrl+Shift+Z)', 'Rehacer (Ctrl+Shift+Z)'],
  'Fundo do quadro (G)': ['Board background (G)', 'Fondo de la pizarra (G)'],
  'Copiar o quadro como imagem (Ctrl+C) — depois é só colar no chat ou e-mail': ['Copy the board as an image (Ctrl+C) — then just paste it into a chat or email', 'Copiar la pizarra como imagen (Ctrl+C) — luego solo pégala en un chat o correo'],
  'Salvar o quadro na pasta (Ctrl+S)': ['Save the board to the folder (Ctrl+S)', 'Guardar la pizarra en la carpeta (Ctrl+S)'],
  'Mais: salvar como, colar, limpar': ['More: save as, paste, clear', 'Más: guardar como, pegar, limpiar'],
  'Fechar o quadro (Esc) — o desenho fica guardado': ['Close the board (Esc) — the drawing is kept', 'Cerrar la pizarra (Esc) — el dibujo se conserva'],
  'Selecione a área que será gravada · clique numa janela ou em qualquer lugar para a tela inteira · Esc para sair': ['Select the area to record · click a window, or anywhere for the full screen · Esc to exit', 'Selecciona el área que se grabará · haz clic en una ventana o en cualquier lugar para la pantalla completa · Esc para salir'],
  'Arraste para selecionar · clique numa janela · C copia a cor · Esc para sair': ['Drag to select · click a window · C copies the color · Esc to exit', 'Arrastra para seleccionar · haz clic en una ventana · C copia el color · Esc para salir'],
  'Gravar': ['Record', 'Grabar'],
  'Começar a gravar (Enter)': ['Start recording (Enter)', 'Empezar a grabar (Enter)'],
  'Tela inteira': ['Full screen', 'Pantalla completa'],
  'Cancelar (Esc)': ['Cancel (Esc)', 'Cancelar (Esc)'],
  'Mais formas': ['More shapes', 'Más formas'],
  'Copiar (Ctrl+C)': ['Copy (Ctrl+C)', 'Copiar (Ctrl+C)'],
  'Salvar na pasta (Ctrl+S)': ['Save to folder (Ctrl+S)', 'Guardar en la carpeta (Ctrl+S)'],
  'Salvar como… (Ctrl+Shift+S)': ['Save as… (Ctrl+Shift+S)', 'Guardar como… (Ctrl+Shift+S)'],
  'Fixar na tela (Ctrl+P)': ['Pin to screen (Ctrl+P)', 'Fijar en pantalla (Ctrl+P)'],
  'Copiar o texto da imagem (Ctrl+T)': ['Copy the text in the image (Ctrl+T)', 'Copiar el texto de la imagen (Ctrl+T)'],
  'Gravar esta área': ['Record this area', 'Grabar esta área'],
  'Colar imagem ou texto (Ctrl+V)': ['Paste image or text (Ctrl+V)', 'Pegar imagen o texto (Ctrl+V)'],
  'Limpar o quadro': ['Clear the board', 'Limpiar la pizarra'],
  'Tecla {0}': ['Key {0}', 'Tecla {0}'],
  'Outra cor': ['Other color', 'Otro color'],
  'Espessura': ['Thickness', 'Grosor'],
  'Preenchimento': ['Fill', 'Relleno'],
  'Nenhum': ['None', 'Ninguno'],
  'Suave': ['Soft', 'Suave'],
  'Sólido': ['Solid', 'Sólido'],
  'Traço': ['Stroke', 'Trazo'],
  'Contínuo': ['Solid', 'Continuo'],
  'Tracejado': ['Dashed', 'Discontinuo'],
  'Preciso': ['Precise', 'Preciso'],
  'À mão': ['Hand-drawn', 'A mano'],
  'Fonte': ['Font', 'Fuente'],
  'Tamanho do texto': ['Text size', 'Tamaño del texto'],
  'Cor {0} copiada': ['Color {0} copied', 'Color {0} copiado'],
  'Sistema': ['System', 'Sistema'],
  'Arredondada': ['Rounded', 'Redondeada'],
  'Manuscrita': ['Handwritten', 'Manuscrita'],
  'Serifada': ['Serif', 'Con serifa'],
  'Caneta': ['Pen', 'Lápiz'],
  'Marca-texto': ['Highlighter', 'Resaltador'],
  'Linha': ['Line', 'Línea'],
  'Seta': ['Arrow', 'Flecha'],
  'Seta dupla': ['Double arrow', 'Flecha doble'],
  'Retângulo': ['Rectangle', 'Rectángulo'],
  'Elipse': ['Ellipse', 'Elipse'],
  'Losango': ['Diamond', 'Rombo'],
  'Passo numerado': ['Numbered step', 'Paso numerado'],
  'Nota adesiva': ['Sticky note', 'Nota adhesiva'],
  'Desfocar / ocultar': ['Blur / hide', 'Desenfocar / ocultar'],
  'Banco de dados': ['Database', 'Base de datos'],
  'Pessoa': ['Person', 'Persona'],
  'Nuvem': ['Cloud', 'Nube'],
  'Balão de fala': ['Speech bubble', 'Globo de diálogo'],
  'Estrela': ['Star', 'Estrella'],
  'Certo': ['Check', 'Correcto'],
  'Errado': ['Cross', 'Incorrecto'],
  'Janela / navegador': ['Window / browser', 'Ventana / navegador'],
  'Celular': ['Phone', 'Celular'],

  // ── imagem fixada, gravação e ditado ──
  'Copiar imagem': ['Copy image', 'Copiar imagen'],
  'Tamanho original': ['Original size', 'Tamaño original'],
  'Fechar': ['Close', 'Cerrar'],
  'Parar e salvar': ['Stop and save', 'Detener y guardar'],
  'Parar': ['Stop', 'Detener'],
  'Terminar': ['Finish', 'Terminar'],
  'Ouvindo…': ['Listening…', 'Escuchando…'],
  'Transcrevendo…': ['Transcribing…', 'Transcribiendo…'],
  'o atalho': ['the shortcut', 'el atajo'],
  'Diga o que fazer · {0} termina': ['Say what to do · {0} finishes', 'Di qué hacer · {0} termina'],
  'Diga o que fazer com o texto selecionado': ['Say what to do with the selected text', 'Di qué hacer con el texto seleccionado'],
  'Ouvindo · {0} termina': ['Listening · {0} finishes', 'Escuchando · {0} termina'],
  'Ouvindo · solte para terminar': ['Listening · release to finish', 'Escuchando · suelta para terminar'],
};

const LANGS = ['pt', 'en', 'es'];
const LOCALES = { pt: 'pt-BR', en: 'en-US', es: 'es-ES' };
const T = window.__TAURI__;
const pick = l => {
  const code = String(l || '').slice(0, 2).toLowerCase();
  return LANGS.includes(code) ? code : 'en';
};

let lang = pick(navigator.language);
try { if (T) lang = pick(await T.core.invoke('get_language')); } catch { }
document.documentElement.lang = LOCALES[lang];

/** Language in use: "pt", "en" or "es". */
export const getLang = () => lang;
/** Locale for numbers and dates ("pt-BR", "en-US", "es-ES"). */
export const locale = () => LOCALES[lang];

/** Translates the Portuguese text and fills {0}, {1}… with the values. */
export function t(pt, ...args) {
  const e = D[pt];
  const s = lang === 'pt' || !e ? pt : e[lang === 'en' ? 0 : 1];
  return args.length ? s.replace(/\{(\d+)\}/g, (m, i) => (i < args.length ? String(args[i]) : m)) : s;
}

// Static HTML: text nodes and the title, placeholder, aria-label and alt attributes whose
// Portuguese text is a key. The original is remembered, so the page can change language again.
const ATTRS = ['title', 'placeholder', 'aria-label', 'alt'];
const original = new WeakMap();
export function translatePage(root = document.body) {
  document.documentElement.lang = LOCALES[lang];
  if (!original.has(document)) original.set(document, document.title);
  if (document.title) document.title = t(original.get(document));
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (n.parentElement && /^(SCRIPT|STYLE|TEXTAREA)$/.test(n.parentElement.tagName)) continue;
    if (!original.has(n)) {
      const key = n.nodeValue.trim();
      if (!key || !(key in D)) continue;
      original.set(n, n.nodeValue);
    }
    const raw = original.get(n);
    const key = raw.trim();
    n.nodeValue = raw.replace(key, t(key));
  }
  for (const el of root.querySelectorAll(ATTRS.map(a => `[${a}]`).join(','))) {
    let saved = original.get(el);
    for (const a of ATTRS) {
      if (!el.hasAttribute(a)) continue;
      if (!saved || !(a in saved)) {
        const key = el.getAttribute(a);
        if (!(key in D)) continue;
        saved = { ...saved, [a]: key };
        original.set(el, saved);
      }
      el.setAttribute(a, t(saved[a]));
    }
  }
}

// When the language changes in the settings, every open page hears it.
const handlers = [];
/** Runs `fn` after the language changes (the new language is already in use). */
export const onLanguageChange = fn => { handlers.push(fn); };
if (T) {
  T.event.listen('language-changed', e => {
    lang = pick(e.payload);
    document.documentElement.lang = LOCALES[lang];
    for (const fn of handlers) fn(lang);
  });
}
