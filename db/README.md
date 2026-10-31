# Base de datos inicial

`schema.sql` contiene el esquema inicial de roles, usuarios, cursos, módulos, compras,
períodos de suscripción y módulos completados. Define almacenamiento y restricciones;
los casos de uso de acceso, cobro y progreso todavía no están implementados.

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
- `courses`: título, descripción, duración estimada positiva en minutos y nivel
  `BEGINNER`, `INTERMEDIATE` o `ADVANCED`.
- `course_modules`: relación con un curso, título, descripción opcional,
  posición positiva única por curso y porcentaje mayor que cero y hasta 100,
  con dos decimales. El porcentaje es un atributo del módulo, no del usuario.
- `course_purchases`: compras confirmadas, una por usuario y curso, con acceso
  sin vencimiento. Conserva el importe y la moneda de la compra aunque cambien
  los precios futuros. No se deben insertar intentos de pago en esta tabla.
- `subscriptions`: cada fila es un período adquirido de acceso a todo el catálogo,
  incluidos cursos agregados durante su vigencia. Se incluye el inicio y se excluye
  el fin del intervalo. No se guarda un estado `ACTIVE` que pueda quedar desactualizado.
  No se fija una duración ni un precio comercial en el esquema.
- `module_completions`: registra una sola finalización por usuario y módulo.
  Se conserva aunque venza la suscripción; consultar el progreso no concede acceso.
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
Al completar todos, debe ver un 100 %. No se calcula a partir del tiempo de sesión.

La suma de los pesos debe ser exactamente `100.00` por curso. El esquema solo
valida el rango individual: **todavía no garantiza la suma entre módulos**.
El futuro caso de uso deberá guardar el conjunto de módulos en una transacción,
bloquear primero la fila del curso y validar la suma antes del commit. Todos los
caminos de escritura deberán respetar ese bloqueo. No habilitar cursos para consumo
con una configuración incompleta. No truncar un total inválido a 100 para ocultarlo.

Antes de registrar una finalización, el caso de uso deberá verificar acceso vigente
y pertenencia del módulo al curso solicitado. Las claves foráneas comprueban
existencia, pero no autorización. El porcentaje se consulta sumando los pesos de
los módulos completados del curso, con resultado cero cuando no hay finalizaciones.

## Reglas pendientes de implementar o definir

- Evitar períodos de suscripción superpuestos para un usuario dentro de una
  transacción que bloquee su fila. La restricción única de inicio solo evita dos
  períodos con exactamente el mismo inicio; no garantiza ausencia de solapamientos.
- Definir precios, monedas admitidas, periodicidad y flujo de renovación. El modelo
  permite registrar nuevos períodos sin sobrescribir el historial anterior.
- Definir cancelaciones y reembolsos antes de implementar cobros. Actualmente no
  hay revocación de compras ni de períodos adquiridos, ni integración con pagos.
- Definir cómo cambiar contenidos y pesos de cursos que ya tienen alumnos: esos
  cambios alterarían el progreso calculado. No implementar edición de esos cursos
  hasta acordar una política de bloqueo o versionado.

## Validación realizada

Se revisaron el SQL y los cambios de formato. No se ejecutó el esquema en MySQL:
el cliente `mysql` no está disponible en la terminal y el motor de Docker está
detenido. Queda pendiente validar creación, claves foráneas, duplicados y valores
inválidos en una base de datos de desarrollo aislada.
