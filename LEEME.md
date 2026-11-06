# Puesta en marcha

1. Creá un proyecto en supabase.com.
2. Authentication > Sign In / Providers: activá "Allow anonymous sign-ins" (y, si podés, CAPTCHA para evitar spam).
3. SQL Editor: pegá y ejecutá `supabase.sql`.
4. Authentication > Users: creá tu usuario (correo y contraseña) y ejecutá la última línea comentada del SQL con tu correo.
5. En `ludmi.html` y `admin.html` reemplazá SUPABASE_URL y SUPABASE_ANON_KEY (Project Settings > API). La anon key es pública por diseño; la seguridad la dan las políticas del SQL.
6. Subí la carpeta a GitHub e importala en Vercel (o `npx vercel`). Quedan: /ludmi (landing) y /admin (tu panel).
7. En ludmi.html completá "Autorización: [COMPLETAR]" y ajustá los textos a lo que realmente ofrecés.

# Editar la landing desde el panel (agregado)

1. Ejecutá `supabase-landing.sql` en el SQL Editor de Supabase (se puede repetir sin problema).
2. Reemplazá `ludmi.html` y `admin.html` en tu repositorio (ya traen tu URL y clave).
3. Entrá a /admin y tocá "⚙ Landing": ahí cambiás textos, imágenes, contactos, plataformas y juegos.
   Los cambios se ven en /ludmi apenas tocás "Guardar cambios", sin volver a publicar en Vercel.

# Links y datos para transferir (agregado)

- En "⚙ Landing" cada plataforma y cada juego tiene un campo "Link al tocar la imagen".
- En "⚙ Landing" > "Datos para transferir" cargás las cuentas (banco, titular, CBU/CVU, alias).
  Se muestran dentro del chat con botón "Copiar". Solo las ve quien abre el chat.
- Volvé a ejecutar `supabase-landing.sql` (es seguro repetirlo): ahora separa lo público de lo que solo ve el chat.

# Instagram y envío de cuentas por el chat (agregado)

- En "⚙ Landing" hay una sección "Instagram": escribí @tuusuario o pegá el link. Sale como botón arriba de los demás contactos.
- En un chat, el botón 💳 (a la izquierda del cuadro de texto) manda las cuentas activas al visitante.
  Las ve como una tarjeta con botones "Copiar". No hace falta volver a ejecutar ningún SQL.

# Íconos en los botones de contacto (agregado)

- En "⚙ Landing" > "Botones de contacto" cada botón tiene un tipo: WhatsApp, Instagram, Chat de la página (abre el chat) u Otro enlace.
- Cada tipo trae un ícono genérico. Para usar el logo oficial (o cualquier ícono propio), subilo en "Ícono propio".
- La sección "Instagram" también tiene su propio "Ícono propio".
- No hace falta ejecutar ningún SQL nuevo.

# Íconos del chat (agregado)

- En "⚙ Landing" > "Íconos del chat" podés subir tu propio ícono para el micrófono, adjuntar, enviar y el botón de transferencias.
- Si no subís nada, se usa el emoji por defecto. No hace falta ejecutar ningún SQL nuevo.

# Botón flotante de chat (agregado)

- En "⚙ Landing" > "Botón flotante de chat" podés prenderlo/apagarlo, cambiar el texto, subir un ícono propio y elegir si se ve siempre o solo cuando el usuario baja.
- No hace falta ejecutar ningún SQL nuevo.

# Nuevo chat para el usuario (agregado)

- El chat tiene ahora encabezado con tu foto y nombre, estado (en línea / desconectado), aviso de conexión, saludo en varios mensajes,
  botones rápidos (Cargar / Retirar / Soporte) y una tarjeta de transferencia con "Copiar CBU", "Copiar alias" y "Subir comprobante".
- Todo se edita en "⚙ Landing" > "Chat" y "Botones rápidos del chat". Hay estilo Claro (tipo WhatsApp) u Oscuro (violeta).
- "En línea" se muestra solo mientras tenés abierto el panel /admin.
- No hace falta ejecutar ningún SQL nuevo.

# Aviso de "datos mostrados" en el panel (agregado)

- Cuando al usuario se le muestran los datos para transferir (botón CARGAR, o al abrir el chat y escribir su primer mensaje),
  en tu chat del panel aparece la línea "💳 Se le mostraron los datos para transferir" con la hora.
- En la lista de chats el aviso se ve como vista previa y no suma como mensaje sin leer.
- No hace falta ejecutar ningún SQL nuevo.

# Orden de la página, desplegables y mensaje de CARGAR en el panel (agregado)

- "⚙ Landing" > "Orden de la página": subís/bajás cada sección con las flechas y la escondés con "Mostrar".
  Orden por defecto: bono, botón verde, plataformas, juegos, cajitas, desplegables, contacto. Arriba quedan siempre foto/nombre/título y abajo el texto legal.
- "⚙ Landing" > "Desplegables": título de la sección (ej. Retiros) y tantos desplegables como quieras (título + explicación).
- Cuando el usuario toca CARGAR, en tu chat del panel aparece el mismo mensaje con las cuentas que él ve.
- No hace falta ejecutar ningún SQL nuevo.

## Sonido, cerrar chats, editar/eliminar y respuestas automáticas
1. **Ejecutá una vez `supabase-chat.sql`** en Supabase > SQL Editor (y volvé a subir `ludmi.html` y `admin.html` a GitHub con esos nombres exactos).
2. **Sonido**: el panel suena con cada mensaje nuevo (incluso de chats que no tenés abiertos). Botón 🔔/🔕 arriba para silenciarlo. El navegador exige un toque en la pantalla para habilitar el audio; si la pestaña está en segundo plano puede que no suene, pero el título muestra `(n)`.
3. **Cerrar chats**: botón "✓ Cerrar chat" arriba del chat. Pasa a la pestaña *Cerrados* y vuelve solo a *Abiertos* cuando el usuario escribe.
4. **Editar/eliminar**: en tus mensajes de texto tocá `⋯` → Editar / Eliminar (imágenes y audios solo se pueden eliminar). El usuario lo ve al instante. Eliminar oculta el mensaje; el archivo queda guardado en Supabase.
5. **Botones rápidos**: en Editor de landing > Botones rápidos elegí "muestra una respuesta automática" y escribí el texto (admite varias líneas y links https). El usuario lo ve como mensaje tuyo y en tu panel queda registrado qué respuesta vio.

## Panel estilo WhatsApp Web y landing renovada
- Panel: buscador arriba (busca por nombre y por texto, incluso en chats cerrados) y filtros **Todos / No leídos / Cerrados**, sin números. Los chats con mensajes sin leer se marcan con un globito verde; el filtro "No leídos" muestra un punto verde cuando hay alguno.
- Landing: nuevo diseño (tarjetas de vidrio, avatar con aro de color, botón con brillo, animación suave de entrada). Todo sigue siendo editable desde el panel; no hay que volver a configurar nada.

## Editor de landing renovado
Menú lateral por secciones (Página, Contenido, Contacto, Chat), una sección a la vez, y vista previa en vivo del celular a la derecha (en pantallas chicas, botón "👁 Vista previa"). Al entrar a las secciones del chat, la vista previa abre el chat. Aviso "● Sin guardar" hasta que guardás. Hay que volver a subir `admin.html` y `ludmi.html` (la vista previa usa la propia landing).

## Bandeja compartida, siempre conectado, notificaciones y tonos
1. **Ejecutá `supabase-chat2.sql`** (una vez, en Supabase > SQL Editor) y volvé a subir `admin.html`.
2. Bandeja: solo **Todos** y **No leídos**. "Cerrar chat" lo saca de la bandeja hasta que el usuario escriba de nuevo. Los cerrados se pueden encontrar con el buscador (aparecen con "✓ Cerrado") y reabrir.
3. Varios administradores: lo leído o contestado por uno deja de figurar como pendiente en los demás (se guarda en Supabase).
4. Siempre conectado: el panel se reconecta solo si se corta la conexión y revisa mensajes nuevos cada 15 segundos, al volver a la pestaña y al recuperar internet, sin recargar.
5. Botón ⚙: elegir tono (8 opciones), volumen, y activar las notificaciones del escritorio (el navegador pide permiso una vez).

## Tildes de "visto"
Ejecutá `supabase-recibos.sql` una vez y volvé a subir `admin.html` y `ludmi.html`.
- En tu panel, cada mensaje tuyo muestra ✓ (enviado) y ✓✓ azul (el usuario lo vio: tenía el chat abierto con la pestaña visible). La lista de chats también muestra el tilde del último mensaje.
- En el chat del usuario, sus mensajes muestran ✓ y ✓✓ azul cuando un agente abrió el chat y los leyó (cuenta como leído solo con la ventana del panel a la vista).
- Editar y eliminar mensajes: botón `⋯` en cada mensaje tuyo (ya incluido; requiere `supabase-chat.sql`).

## Nombre de usuario del visitante
Ejecutá `supabase-usuario.sql` una vez y volvé a subir `admin.html` y `ludmi.html`. Al abrir el chat, el visitante ve un campo "¿Cuál es tu usuario?". Al guardarlo, aparece en tu panel como nombre del contacto. Si vos le ponés un nombre (tocando el título del chat), el tuyo tiene prioridad. Se puede desactivar o cambiar el texto en Editor de landing > Ventana de chat.

## Ruleta de bonos
Subí `ludmi.html` y `admin.html` (no hay SQL nuevo). Editor de landing > Ruleta de bonos: premios y "peso" (probabilidad), textos, mensaje que se envía al chat ({premio}), respuesta automática, una sola vez por persona y mostrar probabilidades. Se puede mover de lugar en "Orden de la página" (por defecto va debajo del botón verde).
Cómo funciona: GIRAR → gira → FRENAR → desacelera hasta el premio sorteado (el sorteo es por peso; frenar no cambia el resultado) → se abre el chat y se envía "Quiero mi bono X%". Limitaciones: el sorteo corre en el navegador del usuario y "una vez por persona" se guarda en ese navegador (se puede saltear borrando datos); es una promoción, validá cada bono antes de acreditarlo.

### Ruleta: solo la primera vez
Editor de landing > Ruleta de bonos > "Cuándo aparece": **Ventana emergente, solo la primera vez** (por defecto) o **Siempre visible dentro de la página**. En la primera visita sale a los ~1 segundo como ventana emergente; al girar y terminar, se cierra y se abre el chat con "Quiero mi bono X". Si la cierran sin girar (✕, Esc o tocando afuera) tampoco vuelve a salir en ese navegador. Subí `ludmi.html` y `admin.html`.

## Usuario obligatorio y único (Juan00, Juan01…)
1. Ejecutá `supabase-usuario2.sql` (después de `supabase-usuario.sql`) y subí `ludmi.html` y `admin.html`.
2. Para chatear hay que poner un nombre o apodo. Hasta entonces el chat no muestra mensajes ni la barra de escritura. El sistema le saca los números del final y le agrega los 2 primeros libres: Juan → Juan00, otro Juan → Juan01, etc. (hasta 99 por nombre). Sin espacios ni símbolos raros.
3. El nombre no se puede cambiar después desde la landing; vos podés ponerle otro nombre al contacto desde el panel. Los usuarios cargados antes de este cambio se conservan como estaban.
4. Los mensajes automáticos (por ejemplo el de la ruleta) esperan a que la persona ponga su nombre y salen después.

## Eliminar chats
Ejecutá `supabase-eliminar.sql` una vez y subí `admin.html` y `ludmi.html`. En el encabezado de cada chat hay un botón 🗑: pide confirmación y borra mensajes, fotos y audios, el nombre de contacto, el usuario y el estado del chat. También desaparece de la pantalla del usuario y de los otros administradores en vivo. No se puede deshacer.

## Editor de landing profesional
Subí `admin.html` y `ludmi.html`. Barra superior (Volver, nombre, estado Guardado / Sin guardar, Guardar cambios, Vista pública), 8 pestañas (Perfil, Pagos, Diseño, Plataformas, Contacto, Chat, Ruleta, Retiros) y vista previa en vivo del celular a la derecha. El botón Guardar solo se habilita cuando hay cambios. También se corrigió que al quitar la foto de perfil se veía un ícono roto en lugar de la corona.

## Panel de chats estilo WhatsApp Web (solo admin.html)
- Tema claro: barra lateral de íconos (sonido, tono/notificaciones, editor de landing, salir), buscador redondeado, chips "Todos / No leídos", lista con avatar, vista previa, hora e insignia verde.
- Chat con fondo beige con dibujitos, burbujas blancas (entrantes) y verde claro (salientes), tildes grises/azules, barra de escritura redondeada con clip, tarjeta, micrófono y enviar.
- No requiere SQL: solo reemplazá admin.html en GitHub.

## App instalable (PWA)
Subir TODOS estos archivos a la raíz del repo (junto a ludmi.html y admin.html): manifest.webmanifest, manifest-admin.webmanifest, sw.js, vercel.json (reemplaza el anterior) y los 8 .png (icon-*, admin-*, apple-touch-icon, admin-apple-touch-icon).
- Landing: botón «📲 Instalar app» (Android/PC al tocar; iPhone muestra cómo hacerlo con Compartir > Agregar a inicio). Editor de landing > Diseño > «App instalable»: se puede desactivar y cambiar el texto.
- Admin: ícono de instalar en la barra izquierda (aparece solo si el navegador permite instalar).
- Para cambiar el logo de la app, reemplazá los .png por los tuyos (mismos nombres y tamaños).
- No hay notificaciones push todavía (el aviso sigue necesitando la pestaña/app abierta).
- Ícono de la app: logo Caja Ludmi (reemplazar los .png para cambiarlo).

## Avisos push (app cerrada)
1. Supabase > SQL Editor: ejecutar supabase-push.sql (NO subirlo a GitHub).
2. Supabase > Edge Functions > Deploy a new function > "Via Editor": nombre `push-notify`, pegar push-notify/index.ts, DESACTIVAR "Verify JWT" (queda protegida por el secreto), Deploy.
3. Edge Functions > Secrets: cargar los 4 valores de PUSH-CLAVES.txt (VAPID_PUBLIC, VAPID_PRIVATE, VAPID_SUBJECT, PUSH_SECRET).
4. GitHub: reemplazar sw.js, ludmi.html y admin.html.
5. Admin: ⚙ (tono y notificaciones) > "Activar avisos". Visitantes: campanita 🔔 en el chat (se puede quitar en el editor > Diseño > App instalable).
- iPhone: los avisos solo funcionan con la app instalada (iOS 16.4+).
- Si no llegan: Edge Functions > push-notify > Logs.

## Modo nocturno (admin.html)
Botón luna/sol en la barra izquierda (en el celular, en el encabezado). Se recuerda por dispositivo; la primera vez sigue el modo del sistema.

## Estadísticas de visitas
1. Supabase > SQL Editor: ejecutar supabase-visitas.sql.
2. GitHub: subir api/visit.js (carpeta `api` en la raíz, junto a ludmi.html), y reemplazar ludmi.html y admin.html. Vercel despliega solo la función.
3. Admin: botón de gráfico (📊 en el celular) > Visitas: hoy / 7 / 30 días, país, ciudad, origen, dispositivo y conversión a chat.
- Cuenta una visita por sesión. No guarda IP. Para medir anuncios usar ?utm_source=instagram&utm_campaign=nombre.

## Lo leído no retrocede + generador de links
- supabase-leidos.sql (SQL Editor): la fecha de "leído" nunca retrocede aunque dos agentes marquen a la vez. admin.html además recuerda lo leído en cada dispositivo.
- Visitas > «Generador de links para anuncios»: arma el link con utm_source y utm_campaign.

## Tildes ✓✓ (revisión)
- Volver a ejecutar supabase-recibos.sql (se puede repetir) y luego supabase-leidos.sql.
- El panel ahora muestra en la línea gris de arriba «⚠ tildes: …» con el motivo si algo falla (antes se desactivaba en silencio).
- La landing consulta cada 12 s si ya leyeron sus mensajes (respaldo si falla la conexión en vivo).

## Promociones (carrusel de imágenes)
Editor de landing > pestaña «Promos»: subí imágenes (ideal 1080×1080 o 1080×1350), título opcional y botón. El botón abre el chat con el mensaje ya escrito, o un link. Se ubica con «Orden de la página» (por defecto aparece después de la ruleta). Solo hay que reemplazar ludmi.html y admin.html; luego, en el editor, «Guardar cambios».

## Cambiar nombre de contactos
Botón ✏ junto al nombre del chat (o tocar el nombre): abre una ventana propia (ya no usa el cuadro del navegador, que se puede bloquear). Vacío = vuelve al usuario original. Si falla, muestra el motivo.

## Ruleta: evitar que clientes ya cargados reclamen de nuevo
Editor > Ruleta:
- «Mostrar la ruleta solo si el link trae ?bono=1»: usar ludmibox.vercel.app/ludmi?bono=1 en los anuncios; el link normal no muestra la ruleta.
- «Botón Ya tengo cuenta»: salta la ruleta, abre el chat y no vuelve a mostrarla en ese dispositivo.
- En el panel, los chats que giraron la ruleta muestran la etiqueta «🎡 Bono X».
- La protección real: acreditar el bono solo a cuentas nuevas con su primera carga (se controla en el casino).

## Links en el chat
Cualquier http(s):// o www. escrito en el chat se vuelve tocable (en la landing, los de los agentes; en el panel, los de ambos). Se abren en otra pestaña.

## Cargar crédito en la pantalla principal + cartel superior
- Botón «Cargar crédito» debajo del botón verde: desplegable con las cuentas (las de «Datos para transferir»), botones para copiar y «Enviar comprobante» (la imagen va directo al chat; si falta el nombre de usuario, se lo pide). Editor > Pagos > «Cargar crédito (pantalla principal)». Se mueve/oculta en «Orden de la página».
- Cartel verde con texto deslizante arriba de todo para instalar la app (toque = instalación; en iPhone y en el navegador de Instagram/Facebook muestra cómo hacerlo). Editor > Diseño > «App instalable».
- Corregido: los botones «Copiar» del chat habían heredado por error el estilo de los botones de promos.

## Plataformas/juegos en movimiento y botón neón
- Editor → **Plataformas**: "Movimiento automático" + velocidad (lenta/media/rápida). Editor → **Juegos**: "Movimiento automático".
- El visitante lo frena tocando/manteniendo, arrastrando con el dedo o mouse, pasando el mouse por encima, o con el botón ⏸/▶. Retoma solo a los ~3 s.
- Con pocas plataformas (que entran en pantalla) queda quieto. Respeta "reducir movimiento" del sistema.
- Editor → **Pagos → Cargar crédito**: casilla "Luz neón animada" (activada por defecto).
- Subir ludmi.html y admin.html, recargar con Ctrl+F5 y "Guardar cambios".

## Pop-up de descarga y Estados (tipo WhatsApp)
- Editor → Diseño → **Pop-up de descarga**: título, texto, botón, cartel verde (Caja Ludmi · Atención por chat), segundos de espera y frecuencia (una vez por visita / por día / siempre). Solo aparece donde se puede instalar la app.
- Editor → **Estados**: imágenes (ideal 1080×1920) con texto, botón opcional (abre el chat con mensaje o un link) y vencimiento opcional (6 h a 7 días). Al tocar el logo de la landing se abren a pantalla completa; el círculo queda gris cuando ya los vieron.
- Botones "Ver en la vista previa" para probarlos sin salir del editor.
- Subir ludmi.html y admin.html, Ctrl+F5 y "Guardar cambios".

## Sistema de Gestión (/gestion) — Admin y Operador

Página aparte: `tudominio.com/gestion` (archivo `gestion.html`). No toca el chat ni la landing.

**Instalación (una sola vez)**
1. Subí `gestion.html` junto a los demás archivos (Vercel lo sirve en `/gestion`).
2. Supabase → SQL Editor → pegá y corré todo `supabase-gestion.sql`.
3. Supabase → Authentication → Users → *Add user*: creá **2 usuarios** con mail + contraseña (tildá *Auto Confirm User*): uno para el ADMIN y uno para el OPERADOR (compartido por todos los cajeros).
4. En el SQL Editor corré, con tus mails reales:
```
insert into public.g_roles(user_id,role) select id,'admin'    from auth.users where email='MAIL_ADMIN'    on conflict (user_id) do update set role='admin';
insert into public.g_roles(user_id,role) select id,'operador' from auth.users where email='MAIL_OPERADOR' on conflict (user_id) do update set role='operador';
```

**Cómo se usa**
- *Operador*: entra con el usuario compartido → elige su nombre y pone su contraseña (o "Soy nuevo · Crear usuario": nombre/apodo + contraseña). Ese nombre queda en cada carga/retiro/gasto del turno. "Cambiar turno" cierra el turno.
- *Operador ve*: Dashboard (sin métricas), Billeteras, Fichas, Movimientos (últimos N días), Gastos, Publicidad (solo "+1 mensaje").
- *Admin ve además*: Cajeros y sueldos, números de Publicidad (inversión, ROI), Métricas, Ajustes y Auditoría. Es el único que crea billeteras/fichas, hace ajustes, transferencias, paga sueldos y cambia claves.
- En Ajustes el admin decide si el operador puede editar/anular movimientos y cuántos días de historial ve.
- Los permisos los hace cumplir la base de datos (RLS): aunque alguien abra la consola del navegador, el operador no puede leer sueldos ni métricas.
- Cada carga/retiro/gasto mueve saldos de billetera y fichas en una sola operación; editar o anular los revierte solos.
