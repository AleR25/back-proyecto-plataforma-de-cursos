# Plan de trabajo del backend

## Objetivo y forma de trabajo

Construir una API de la plataforma de cursos con Java 21, Spring Boot, MySQL
y arquitectura hexagonal, respetando el `pom.xml` y las reglas acordadas.
El primer objetivo es un recorrido completo: registrarse, iniciar sesión,
consultar un curso publicado, obtener acceso y registrar progreso.

Trabajar por funcionalidades completas: dominio y puertos, caso de uso,
persistencia, endpoint, autorización, documentación y pruebas. No crear primero
todas las entidades y dejar las reglas de negocio para el final.

El dominio será independiente de Spring y JPA. Los casos de uso dependerán de
puertos; infraestructura resolverá HTTP, seguridad, persistencia, almacenamiento
de videos y transacciones. Cada etapa debe dejar resultados verificables.

## Reglas confirmadas

- Un rol por usuario. Catálogo inicial: `STUDENT`, `INSTRUCTOR`, `ADMIN`.
- Registro con nombre de usuario y contraseña; contraseña almacenada mediante hash.
- ID interno consecutivo y UUID v4 público, generado por el servidor.
- Texto en español admitido; identificadores de código y base de datos en inglés.
- Compra individual con acceso sin vencimiento; suscripción a todo el catálogo.
- Suscripción mensual con fecha original como referencia: el día 31 se ajusta al
  último día de meses cortos y se recupera cuando vuelva a existir.
- Curso con módulos cuyos pesos suman 100 %, y lecciones con videos.
- Lección completa al reproducir al menos el 90 % sin duplicar fragmentos ni contar saltos.
- Un módulo se completa al completar sus lecciones. Las finalizaciones reconocidas
  se conservan, aunque después se agregue contenido.
- El progreso reconocido nunca disminuye; un curso terminado sigue al 100 %.
- Se permiten reemplazos de video y ampliaciones del curso, conservando ese progreso.
- La auditoría se decidirá al final; seguridad y autorización se implementan desde el inicio.

## Etapa 1 — Base técnica y validación de MySQL

- Preparar configuración local y de pruebas con variables de entorno, sin secretos versionados.
- Ejecutar el esquema y las pruebas mensuales en una instancia MySQL aislada.
- Verificar claves foráneas, CHECK, UUID, caracteres en español, unicidad y vistas.
- Separar el reinicio destructivo de pruebas del esquema destinado a evolucionar.
- Adoptar migraciones versionadas; evaluar Flyway y justificar su incorporación
  antes de agregarlo. Evitar actualización o borrado automático del esquema de producción.
- Revisar compilación y procesamiento de anotaciones: actualmente MapStruct figura
  como procesador de pruebas, pero no en la configuración explícita de compilación principal.
- Establecer errores HTTP consistentes, validación, paginación y documentación OpenAPI.

**Finalización:** proyecto compilable, conexión reproducible a MySQL, esquema
verificado y pruebas que no dependan de una base con datos reales.

## Etapa 2 — Usuarios, autenticación y autorización

- Definir la matriz de permisos de los tres roles antes de habilitar operaciones.
- Elegir y documentar sesiones con cookies o tokens según el cliente previsto;
  configurar CORS, CSRF, expiración y cierre de sesión según esa elección.
- Implementar registro, inicio y cierre de sesión, consulta y edición del perfil propio.
- Asignar `STUDENT` desde el servidor; impedir asignar roles desde el registro público.
- Generar UUID v4, normalizar usuario/correo/teléfono y manejar duplicados concurrentes.
- Usar `PasswordEncoder`; no exponer hashes, credenciales ni el ID interno en respuestas.
- Resolver la identidad desde la autenticación, no desde un identificador enviado por el cliente.

**Finalización:** un usuario puede crear su cuenta y acceder a su perfil; no puede
leer o editar el de otro ni elevar su rol. Pruebas de autenticación, permisos,
duplicados, validaciones y datos sensibles aprobadas.

## Etapa 3 — Cursos, módulos, lecciones y publicación inicial

- Implementar creación de cursos en borrador, edición, orden de módulos/lecciones
  y consulta paginada del catálogo publicado.
- Definir si un curso tiene uno o varios instructores. El esquema actual no define
  esa propiedad: incorporar la relación necesaria antes de autorizar edición por instructor.
- Restringir cada operación por rol y propiedad del recurso; no basta con ser instructor.
- Implementar publicación atómica: existen módulos, cada módulo tiene lecciones
  con video válido y los pesos suman exactamente 100.00.
- Mantener borradores fuera del catálogo del alumno y proteger claves de almacenamiento.
- Probar reordenamientos, posiciones repetidas, publicación inválida y ediciones concurrentes.

**Finalización:** se puede crear y publicar un curso completo, y ningún usuario
sin permiso puede modificarlo. Las ediciones de cursos con progreso se habilitan en la etapa 6.

## Etapa 4 — Compras, suscripciones y acceso

- Implementar los casos de uso para registrar compras confirmadas y períodos adquiridos.
- Conceder acceso cuando exista compra del curso o suscripción vigente; conservar
  compras y progreso al vencer la suscripción.
- Calcular ciclos mensuales desde `billing_anchor_at`, sin sumar meses al fin ajustado anterior.
- Evitar duplicados y solapamientos bajo transacción y bloqueo por usuario.
- Inyectar un reloj para probar vencimientos sin depender de la fecha real.
- Definir antes del flujo comercial: precios, moneda, cancelación, impago,
  reembolso y reactivación después de una interrupción. Confirmar además la zona
  comercial de renovación: actualmente el esquema calcula las fechas en UTC.
- Usar datos de prueba o un adaptador simulado en desarrollo hasta integrar pagos.
  No publicar un endpoint que permita al alumno declarar una compra como pagada.

**Finalización:** acceso correcto con compra o suscripción, rechazo sin derecho
de acceso, recuperación del día 31, años bisiestos y renovaciones simultáneas probados.

## Etapa 5 — Acceso al video y registro de progreso

- Definir un puerto para almacenamiento/video y elegir el servicio antes de integrar
  su adaptador. Guardar referencias estables, no enlaces temporales en la base.
- Entregar acceso al video solo después de validar identidad, curso y derecho de acceso.
- Diseñar el contrato de eventos del reproductor: sesión de reproducción, revisión,
  intervalos, continuidad, pausas, saltos y reintentos. El backend no puede demostrar
  atención humana: validar consistencia y evitar aceptar porcentajes declarados por el cliente.
- Registrar intervalos de la revisión vigente y descontar repeticiones y solapamientos.
- Guardar en la misma transacción el máximo reconocido por lección, las finalizaciones
  de módulos y el máximo del curso. Las vistas por sí solas no persisten esos valores.
- Consultar el progreso propio y tratar ausencia de registros como cero.

**Finalización:** el 89.999 % no completa una lección, el 90 % sí; saltos y repeticiones
no inflan el avance. Los eventos duplicados o concurrentes no reducen ni duplican progreso.

## Etapa 6 — Modificar cursos publicados sin quitar progreso

- Consolidar el progreso previo de los alumnos afectados antes de cambiar contenido o pesos.
- Incrementar `video_revision` al reemplazar un video o modificar su duración.
- Separar los intervalos del video anterior y rechazar eventos tardíos que pretendan
  aplicarse a la revisión nueva.
- Agregar módulos/lecciones y redistribuir los pesos en una sola transacción;
  si la estructura final es inválida, revertir toda la edición.
- Mantener el máximo reconocido: 60 % no baja a 30 %, pero puede subir luego a 70 %;
  no sumar porcentajes históricos a los nuevos pesos. Un 100 % se conserva.
- Mantener un orden de bloqueo consistente con reproducción para evitar carreras.

**Finalización:** reemplazar, alargar o acortar videos y ampliar cursos conserva
el progreso reconocido. Probar edición simultánea con reproducción y fallos con rollback.

## Etapa 7 — Integración de pagos y renovación operativa

Esta etapa depende de resolver las reglas comerciales de la etapa 4 y elegir proveedor.

- Implementar el adaptador de pagos detrás de un puerto del núcleo.
- Confirmar compras y renovaciones únicamente desde notificaciones verificadas del proveedor.
- Procesar eventos repetidos sin duplicar compras, períodos o cobros; no confiar
  en una redirección del navegador como confirmación.
- Coordinar renovación, resultado del cobro, reintentos y vencimiento según la política acordada.
- Probar en el entorno de pruebas del proveedor; ningún cobro real durante desarrollo.

**Finalización:** compra y renovación funcionan de extremo a extremo en pruebas,
con eventos duplicados, fallidos y fuera de orden cubiertos.

## Etapa 8 — Auditoría y preparación de la primera entrega

- Decidir qué acciones requieren historial: cambios de rol, publicación, edición
  de contenido y operaciones comerciales son candidatos, no alcance ya implementado.
- Implementar únicamente la auditoría acordada, sin registrar secretos.
- Revisar consultas, paginación, relaciones JPA y posibles N+1.
- Medir vistas de progreso y contención del bloqueo por curso con datos representativos;
  optimizar solo si las mediciones lo justifican.
- Completar OpenAPI, ejemplos de solicitudes, configuración y guía de ejecución.
- Ejecutar la suite completa y probar una instalación nueva mediante migraciones.

**Finalización:** recorrido completo reproducible, permisos verificados, documentación
actualizada y limitaciones restantes identificadas. Publicar o desplegar requerirá una tarea posterior.

## Criterio de cierre de cada funcionalidad

- Reglas del dominio probadas sin Spring ni base de datos.
- Casos de uso probados con dobles de puertos, incluidos errores y permisos.
- Endpoints probados para validación, respuestas y autorización.
- Persistencia, vistas, restricciones y transacciones probadas contra MySQL real de pruebas.
- OpenAPI y documentación actualizadas; sin secretos ni cambios ajenos en el diff.
- Ejecutar primero pruebas afectadas con Maven Wrapper y después `verify` cuando
  corresponda. Las pruebas SQLite actuales complementan, pero no sustituyen, MySQL.

## Primer bloque de trabajo

Comenzar por la etapa 1 y continuar con el registro/inicio de sesión de la etapa 2.
El primer entregable funcional será una cuenta segura que pueda consultar su perfil.
Luego avanzar al catálogo publicado, acceso y progreso. No iniciar frontend,
certificados o notificaciones como parte de este plan.
