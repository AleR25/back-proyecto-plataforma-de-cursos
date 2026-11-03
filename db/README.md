# Base de datos inicial

`schema.sql` contiene el esquema inicial de roles, usuarios, cursos, módulos, compras,
períodos de suscripción, lecciones y fragmentos de video reproducidos. Las vistas
calculan el progreso por lección y los módulos completados. Los casos de uso de
acceso, cobro y recepción de eventos del reproductor todavía no están implementados.

## Ejecución

Usar únicamente una base de datos descartable de desarrollo en MySQL 8.0.16 o superior.
Los CHECK se aplican desde esa versión, según la
[documentación de MySQL](https://dev.mysql.com/blog-archive/mysql-8-0-16-introducing-check-constraint/).
El script elimina `course_platform` si existe, la vuelve a crear y la selecciona
con `USE`. Cada ejecución borra sus datos anteriores: está preparado para reiniciar
pruebas, no para actualizar una base con datos que deban conservarse.
Spring Boot no lo carga automáticamente desde esta carpeta. Los futuros cambios
en bases con datos necesitarán migraciones independientes.

## Decisiones de esta primera versión

- `users.id`: identificador interno consecutivo `BIGINT AUTO_INCREMENT`. Las
  claves foráneas `user_id` siguen usando este identificador.
- `users.public_id`: UUID v4 obligatorio y único, almacenado como `CHAR(36)` ASCII.
  El CHECK valida el formato canónico en minúsculas, la versión 4 y la variante
  del UUID; no puede comprobar la aleatoriedad del generador.
  Al implementar el alta, el servidor deberá generarlo una sola vez con
  `UUID.randomUUID().toString()` y conservarlo sin cambios. No se acepta desde
  el cliente ni se genera automáticamente en este script. Los INSERT de pruebas
  también deberán proporcionar un UUID v4 válido.
  Las URLs y respuestas públicas deberán usar `public_id` sin exponer `id`.
  Esto no sustituye la autorización de acceso a cada usuario. La generación
  y el uso en la API quedan pendientes de implementar en el backend.
- `roles`: catálogo inicial `STUDENT`, `INSTRUCTOR` y `ADMIN`, con nombres únicos.
  Los permisos concretos de cada rol se definirán al implementar las funcionalidades.
- `users.role_id`: cada usuario debe tener exactamente un rol existente. Varios
  usuarios pueden compartirlo; no hay tabla de múltiples roles por usuario.
  No se puede eliminar un rol mientras tenga usuarios asociados. El registro
  público deberá asignar `STUDENT` desde el servidor, buscando el rol por nombre,
  sin aceptar roles ni permisos enviados por el cliente. Los cambios de rol
  requerirán autorización explícita en la aplicación.
- `users`: nombre de usuario obligatorio y único, hash de contraseña obligatorio.
  Nombre, apellido y correo son opcionales; el correo, si se proporciona, es único.
  La aplicación deberá normalizar espacios y validar formato de correo.
  La comparación de nombres de usuario y correos no distingue mayúsculas,
  pero sí acentos.
- `password_hash`: guardar únicamente el resultado de un `PasswordEncoder`.
  La restricción SQL evita valores vacíos; no comprueba que sea un hash válido.
- `users.phone`: texto opcional de hasta 30 caracteres para conservar `+`, prefijos
  y ceros iniciales. Ausencia se representa con NULL, no con texto vacío. No es
  único. La validación y normalización del número se resolverán en la aplicación.
- `courses`: título, descripción, duración estimada positiva en minutos y nivel
  `BEGINNER`, `INTERMEDIATE` o `ADVANCED`.
  `publication_status` inicia en `DRAFT`; pasa a `PUBLISHED` únicamente tras validar
  la estructura del curso. Se validan los pesos de los módulos, no el progreso
  individual de los alumnos. El campo por sí solo no ejecuta esa validación.
- `course_modules`: relación con un curso, título, descripción opcional,
  posición positiva única por curso y porcentaje mayor que cero y hasta 100,
  con dos decimales. El porcentaje es un atributo del módulo, no del usuario.
- `course_purchases`: compras confirmadas, una por usuario y curso, con acceso
  sin vencimiento. Conserva el importe y la moneda de la compra aunque cambien
  los precios futuros. No se deben insertar intentos de pago en esta tabla.
- `subscriptions`: cada fila es un período adquirido de acceso a todo el catálogo,
  incluidos cursos agregados durante su vigencia. Se incluye el inicio y se excluye
  el fin del intervalo. No se guarda un estado `ACTIVE` que pueda quedar desactualizado.
  Los períodos son mensuales: `billing_anchor_at` guarda la fecha original UTC y
  `billing_cycle` comienza en cero. El CHECK exige inicio = ancla + ciclo meses
  y fin = ancla + (ciclo + 1) meses. El backend debe proporcionar esas fechas.
  Se conserva el ancla al renovar; no se calcula desde el fin del período anterior.
  Ejemplo: 31/01/2027 → 28/02/2027 → 31/03/2027; en 2028 febrero termina el 29.
  Es el ajuste de fin de mes de [DATE_ADD de MySQL](https://dev.mysql.com/doc/refman/8.0/en/date-and-time-functions.html#function_date-add).
  No son períodos fijos de 30 días y no se ejecutan cobros automáticamente.
- `lessons`: cada lección pertenece a un módulo y tiene título, descripción
  opcional, posición única en ese módulo, referencia estable al video y duración
  positiva en segundos con precisión de milisegundos. El video se guarda fuera
  de la base. `video_key` distingue mayúsculas y no debe ser una URL temporal.
  `video_revision` empieza en 1 y debe incrementarse al reemplazar el video o
  cambiar su duración, después de guardar el progreso anterior.
- `lesson_watch_intervals`: fragmentos reproducidos por usuario y lección.
  No se borran al vencer una suscripción; consultar progreso no concede acceso.
  La clave compuesta evita duplicados exactos y `lesson_progress` descuenta
  solapamientos, incluso cuando se vuelve a ver un fragmento en otra sesión.
- Los intervalos incluyen `video_revision`: solo la revisión vigente aporta
  segundos al cómputo actual; el porcentaje previo se conserva en el estado.
- `lesson_progress_state`: máximo porcentaje reconocido por usuario y lección,
  con nueve decimales truncados, nunca redondeados hacia arriba.
- `module_completion_records`: finalizaciones reconocidas. Agregar lecciones
  no revoca la finalización de un módulo ya completado por ese usuario.
- `course_progress_state`: máximo porcentaje reconocido por usuario y curso.
  Un curso terminado conserva 100 %, aunque luego se amplíe.
- `lesson_progress`: vista con segundos de la revisión actual, porcentaje efectivo
  (máximo entre el guardado y el actual) e `is_completed`. El umbral es **90 %**.
  Sin fragmentos válidos ni estado no hay fila: al listar lecciones, usar
  LEFT JOIN y tratar esa ausencia como cero segundos y no completada.
- `module_completions`: une finalizaciones reconocidas con módulos cuyas lecciones
  están completas actualmente. Un módulo vacío no genera una nueva finalización.
- `course_progress`: máximo entre el porcentaje reconocido y la suma actual de
  pesos de módulos completados. No suma ambos valores. Sin estado ni módulos
  completados, la ausencia de fila representa 0 %. Un total actual mayor que 100
  revela un curso inválido: rechazar la configuración en lugar de ocultarlo.
- Los importes usan `DECIMAL(12,2)` y monedas de tres letras mayúsculas.
  La aplicación deberá validar que la moneda exista y esté admitida; el CHECK
  solo comprueba el formato. Esta versión contempla importes con dos decimales.
- Las claves foráneas impiden módulos huérfanos y el borrado de cursos con módulos.
- Las fechas se almacenan en UTC. La aplicación deberá configurar sus conexiones
  en esa zona horaria, además de la sesión usada para ejecutar el script.
- Se mantienen `created_at` y `updated_at` donde ya existen como fechas de creación
  y última modificación. No representan un historial de cambios. La auditoría y
  las tablas que la necesiten se definirán al final, según lo acordado.

## Acceso y progreso

El acceso a un curso se concede si el usuario tiene una compra confirmada de ese
curso **o** un período de suscripción vigente. Vencer la suscripción no elimina
una compra ni los módulos completados. La identidad debe obtenerse de la sesión
autenticada; no basta con un `user_id` enviado por el cliente.

Se conserva la duración estimada como información para el alumno. El porcentaje
representa el peso de cada módulo, independiente de su duración: por ejemplo,
20 %, 30 % y 50 %. Al completar los dos primeros, el alumno ve un 50 %.
Al completar todos, debe ver un 100 %. Cada módulo aporta su peso cuando todas
sus lecciones alcanzan el 90 % o su finalización ya fue reconocida. No se otorga
parte del peso del módulo por lecciones individuales. No se calcula a partir
del tiempo de sesión ni de la posición más avanzada alcanzada en el video.

Ejemplo: en un video de 100 segundos, ver [0, 60) y [30, 90) equivale a 90 segundos,
no a 120. Ver [0, 10) y saltar a [90, 100) solo equivale a 20 segundos. Las vistas
calculan esta unión y limitan el cómputo a la duración del video. El servidor
deberá rechazar intervalos fuera de esa duración antes de guardarlos; el CHECK
solo verifica límites positivos porque la duración está en otra tabla.

La suma de los pesos debe ser exactamente `100.00` por curso. El esquema solo
valida el rango individual: **todavía no garantiza la suma entre módulos**.
El futuro caso de uso deberá guardar el conjunto de módulos en una transacción,
bloquear primero la fila del curso y validar la suma antes del commit. Todos los
caminos de escritura deberán respetar ese bloqueo. No habilitar cursos para consumo
con una configuración incompleta. No truncar un total inválido a 100 para ocultarlo.

Se permite agregar módulos y lecciones después de publicar. El caso de uso deberá
bloquear la fila del curso, guardar el conjunto de cambios y validar nuevamente
que hay módulos, que cada uno tiene lecciones y que sus pesos suman 100.00 antes
del commit. Si falla, se revierte toda la edición y se conserva la estructura
publicada anterior. Al agregar módulos se deben redistribuir los pesos existentes.
La publicación inicial debe realizar esas mismas comprobaciones antes de cambiar
`publication_status`. No se guarda un booleano de validación independiente.

El porcentaje reconocido nunca disminuye. Por ejemplo, si un alumno tenía 60 %
y al redistribuir pesos su avance actual resulta 30 %, sigue viendo 60 %. Cuando
el cálculo actual llegue a 70 %, verá 70 %; no se suman el 60 % anterior y el 30 %.
El contenido nuevo puede estar pendiente aunque el curso ya esté completado.

**Contrato obligatorio del backend, todavía pendiente de implementación:**
en cada operación de reproducción, bloquear primero la fila del curso, validar
acceso y revisión del video, registrar intervalos y guardar el máximo de las vistas
en los estados de lección y curso, junto con nuevas finalizaciones de módulos,
todo en una transacción. Al actualizar estados usar GREATEST(valor guardado,
valor calculado), nunca asignar un valor menor. No borrar estados ni finalizaciones.
Antes de editar videos, lecciones o pesos, consolidar también el progreso previo
de los alumnos afectados bajo el mismo bloqueo. Los eventos tardíos de una revisión
anterior no deben incorporarse al video nuevo. La revisión no expone versiones al
alumno: evita mezclar tiempos y conserva el crédito de aprendizaje reconocido.

Las vistas leen estados, pero no los escriben. Modificar tablas directamente sin
este flujo NO garantiza conservar el progreso. Estos registros son estado actual
del negocio; la auditoría general continúa pendiente según lo acordado.

Antes de registrar fragmentos, el caso de uso deberá verificar acceso vigente
y pertenencia de la lección al módulo y curso solicitados. Las claves foráneas comprueban
existencia, pero no autorización. El porcentaje se consulta mediante `course_progress`,
que considera tanto el cálculo actual como el máximo reconocido.

El backend debe validar eventos y continuidad de reproducción, controlar reintentos
y distinguir saltos de reproducción efectiva. No debe aceptar un `is_completed`,
un total de segundos ni intervalos arbitrarios enviados por el cliente como prueba
de visualización. Las vistas evitan duplicar tiempo, pero no autentican eventos.
El reproductor y ese flujo de validación quedan pendientes de implementación.

## Reglas pendientes de implementar o definir

- Evitar períodos de suscripción superpuestos para un usuario dentro de una
  transacción que bloquee su fila. La restricción única de inicio solo evita dos
  períodos con exactamente el mismo inicio; no garantiza ausencia de solapamientos.
- Implementar la renovación mensual usando siempre la misma `billing_anchor_at`
  e incrementando `billing_cycle`. El inicio del nuevo período coincide con el fin
  del anterior, incluido el ajuste de meses cortos. Las fechas se calculan en UTC,
  como el resto del esquema. Definir precios, monedas admitidas y flujo de cobro.
  La restricción única evita ciclos duplicados para la misma ancla; no impide
  solapamientos entre anclas distintas. El caso de uso debe bloquear al usuario
  y validar todos sus períodos antes de registrar una renovación.
- Definir cancelaciones y reembolsos antes de implementar cobros. Actualmente no
  hay revocación de compras ni de períodos adquiridos, ni integración con pagos.
- Implementar en el backend el contrato de persistencia de progreso descrito
  arriba antes de habilitar reemplazos y ampliaciones de cursos con alumnos.

## Validación realizada

Se revisaron el SQL y los cambios de formato. No se ejecutó el esquema en MySQL:
el cliente `mysql` no está disponible en la terminal y el motor de Docker está
detenido. Queda pendiente validar creación, claves foráneas, duplicados y valores
inválidos en una base de datos de desarrollo aislada. Las consultas de progreso
se verifican aparte con `node --test db/tests/progress-queries.test.mjs` (Node con
soporte de `node:sqlite`), sobre SQLite
en memoria y funciones equivalentes para LEAST/GREATEST/TRUNCATE. Estas pruebas ejecutan
los SELECT de las vistas del esquema, pero no sustituyen una integración MySQL.

Las 13 pruebas cubren el umbral, solapamientos, saltos, separación de usuarios,
reemplazos de video y conservación del porcentaje parcial y completo a partir
de estados previamente guardados. No prueban un backend de escritura, que aún
no existe para este flujo.

`db/tests/monthly-subscriptions.mysql.sql` prueba las restricciones de ciclos
mensuales en MySQL: febrero normal y bisiesto, recuperación del día 31, cambio
de año y rechazo de una renovación desplazada al día 30. Ejecutarlo después del
esquema en una base aislada; revierte sus datos de prueba. Aún no se ejecutó por
falta de un servidor MySQL disponible.
