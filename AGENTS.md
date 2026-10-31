# AGENTS.md — Plataforma de cursos

## Propósito y alcance

Este repositorio contiene el backend de una plataforma de cursos desarrollada en Java con arquitectura hexagonal. Estas instrucciones se aplican a todo el proyecto; las instrucciones de un AGENTS.md más cercano al archivo complementan estas pautas para su ámbito.

Responder y documentar en español. Mantener los identificadores de código en inglés y respetar las convenciones existentes. Implementar solamente el alcance solicitado; no asumir que pagos, certificados, notificaciones u otras funcionalidades están aprobados.

## Stack del proyecto

- Java 21 y Spring Boot. Consultar `pom.xml` como fuente de verdad para versiones y dependencias.
- Maven con los wrappers `mvnw` y `mvnw.cmd`.
- Spring MVC, Spring Data JPA, Spring Security y Bean Validation.
- MySQL como controlador de persistencia declarado.
- MapStruct y Lombok ya disponibles; usarlos cuando aporten claridad y comprobar su configuración de procesamiento de anotaciones antes de depender de código generado.
- Springdoc OpenAPI para documentar la API.
- Paquete raíz: `com.plataformacursos.cursos`.

No cambiar versiones, herramienta de construcción, motor de base de datos o framework sin una necesidad concreta del trabajo solicitado.

## Arquitectura hexagonal

La dirección de dependencias debe apuntar hacia el núcleo. La aplicación depende del dominio; la infraestructura puede depender de ambos. El dominio no depende de aplicación ni infraestructura. Los adaptadores implementan puertos definidos en el núcleo.

### Dominio: `domain`

- `domain.model`: entidades de negocio, objetos de valor e invariantes.
- `domain.ports.in`: contratos de operaciones o casos de uso ofrecidos por el núcleo, siguiendo la convención actual.
- `domain.ports.out`: contratos de repositorios y servicios externos que necesita el núcleo.
- Mantener el dominio independiente de Spring, JPA, HTTP, DTO de transporte y proveedores externos.
- No usar anotaciones como `@Entity`, `@Service` o `@RestController` en modelos y puertos de dominio.
- Expresar las reglas de negocio con métodos e invariantes del dominio. Usar excepciones de negocio sin códigos HTTP.
- Los puertos de persistencia trabajan con modelos del dominio y no exponen entidades JPA, `JpaRepository`, `ResponseEntity` ni tipos de paginación de Spring.

### Aplicación: `application`

- `application.usecase`: implementaciones de casos de uso y orquestación mediante los puertos.
- `application.service`: servicios de aplicación cuando exista una responsabilidad que justifique su presencia; evitar duplicar el mismo flujo entre servicios y casos de uso.
- Mantener los casos de uso independientes de controladores, entidades JPA e implementaciones concretas de repositorios.
- Preferir clases Java simples e inyección por constructor. Registrar sus dependencias desde la configuración de infraestructura.
- Los paquetes existentes `application.dto` y `application.mapper` se pueden conservar para contratos y conversiones en el límite de aplicación. No introducir DTO HTTP ni anotaciones de transporte en el dominio.
- Definir límites transaccionales para operaciones que modifican varios datos de forma atómica. Resolverlos en infraestructura mediante configuración o decoradores sin introducir JPA en el núcleo.

### Infraestructura: `infrastructure`

- Adaptadores de entrada: controladores HTTP que validan solicitudes, convierten datos e invocan puertos de entrada.
- Adaptadores de salida: persistencia JPA, integraciones y mapeo entre entidades y modelos del dominio.
- Configuración: composición de dependencias, seguridad, transacciones y configuración de frameworks.
- Manejo global de errores: traducir fallos de negocio y aplicación a respuestas HTTP sin filtrar detalles internos.
- Los controladores no acceden directamente a repositorios JPA ni contienen reglas de negocio.
- Los repositorios de Spring Data y las entidades JPA permanecen en infraestructura.

### Organización de nuevas funcionalidades

Agrupar por funcionalidad dentro de las capas existentes, siguiendo los paquetes actuales. Como referencia:

```text
com.plataformacursos.cursos
├── domain
│   ├── model/course
│   └── ports
│       ├── in/course
│       └── out/course
├── application
│   ├── usecase/course
│   ├── dto/course
│   └── mapper/course
└── infrastructure
    ├── config
    ├── exceptions
    └── ports
        ├── in/controllers/course
        └── out
            ├── adapters/course
            ├── repository/course
            ├── entity/course
            └── mapper/course
```

Este árbol es una guía para código nuevo, no una afirmación sobre funcionalidades implementadas. No mover paquetes existentes ni realizar una migración general de arquitectura como parte de un cambio pequeño.

## Criterios del negocio

Las áreas posibles incluyen usuarios, cursos, contenidos, inscripciones y progreso. Incorporarlas solo cuando lo requiera la tarea y confirmar las reglas que afecten al comportamiento público.

- Cuando existan roles de estudiante, instructor o administrador, aplicar autorización explícita para cada operación.
- Verificar propiedad del recurso y permisos; no confiar en un identificador de usuario recibido del cliente como prueba de identidad.
- Al implementar inscripciones, definir y probar duplicados, disponibilidad del curso y estados permitidos.
- Al implementar progreso, comprobar inscripción y pertenencia del contenido al curso correspondiente.
- Al implementar publicación de cursos, definir las condiciones y transiciones de estado válidas antes de codificarlas.
- Usar objetos de valor para conceptos con invariantes propias. Si se incorpora dinero, usar `BigDecimal` y una moneda explícita.

## Código, API y persistencia

- Usar nombres que expresen intención, métodos acotados e inyección por constructor.
- Preferir inmutabilidad cuando sea práctica. Evitar setters públicos o Lombok `@Data` indiscriminado en modelos con invariantes.
- Validar formato y obligatoriedad de solicitudes en el límite HTTP; validar reglas de negocio en el núcleo.
- Separar DTO de entrada, DTO de salida, modelo de dominio y entidad de persistencia. No devolver entidades JPA desde la API.
- Mapear de forma explícita los campos sensibles y controlados por el servidor. No permitir que el cliente asigne roles o permisos sin autorización.
- Mantener contratos HTTP consistentes, estados adecuados y errores estables. Actualizar OpenAPI al cambiar endpoints o contratos.
- Paginar consultas de listados que puedan crecer. Revisar consultas N+1 y carga de relaciones cuando afecten al cambio.
- Mantener integridad mediante restricciones de base de datos, además de validaciones de negocio, cuando exista riesgo de concurrencia.
- Usar el mecanismo de migraciones existente. Si hace falta introducir uno, justificar la decisión; no usar cambios destructivos automáticos de esquema para producción.
- No capturar excepciones para ocultar fallos ni devolver éxito ante una operación fallida.

## Seguridad y configuración

- No guardar credenciales, tokens ni secretos en código, pruebas, documentación o archivos versionados. Usar variables de entorno o configuración local excluida de Git.
- No imprimir contraseñas, tokens ni datos personales sensibles en logs o respuestas.
- Codificar contraseñas mediante `PasswordEncoder`; nunca almacenarlas en texto plano ni incluirlas en DTO de respuesta.
- No desactivar autenticación o autorización globalmente para resolver un problema puntual.
- Configurar CORS y CSRF según el mecanismo real de autenticación; no desactivarlos por defecto.
- Mantener perfiles y dependencias externas de desarrollo y pruebas separados de producción.

## Pruebas y comandos

Usar el Maven Wrapper del repositorio. En PowerShell:

```powershell
.\mvnw.cmd test
.\mvnw.cmd verify
.\mvnw.cmd "-Dtest=NombreDeLaPrueba" test
.\mvnw.cmd spring-boot:run
```

En Linux o macOS, usar `./mvnw` con los mismos argumentos. `spring-boot:run` requiere la configuración y los servicios externos correspondientes; no asumir que están disponibles.

- Dominio: pruebas unitarias de invariantes y transiciones, sin contexto de Spring ni base de datos.
- Aplicación: pruebas de casos de uso con dobles de puertos de salida, incluyendo fallos y permisos cuando correspondan.
- Entrada HTTP: pruebas de validación, serialización, errores y autorización.
- Persistencia: pruebas de integración para consultas, mapeos, restricciones y transacciones modificadas. No usar datos o servicios de producción.
- Añadir pruebas relevantes para comportamiento nuevo o correcciones; evitar pruebas que solo reproduzcan la implementación.
- Ejecutar primero las pruebas afectadas y luego `verify` cuando el alcance lo justifique. Si un requisito externo impide ejecutarlas, informar el comando y el bloqueo exacto; no afirmar que pasaron.
- Los cambios solo de documentación no requieren levantar la aplicación ni ejecutar toda la suite.

## Flujo de trabajo de los agentes

1. Leer estas instrucciones y la configuración pertinente antes de editar.
2. Revisar el estado de Git y conservar modificaciones ajenas o previas del usuario.
3. Localizar el comportamiento y sus contratos antes de modificarlo, usando Codebase Memory según el bloque siguiente.
4. Hacer el cambio en la capa responsable con el menor alcance que resuelva el problema.
5. No introducir dependencias, abstracciones, módulos o funcionalidades sin una razón concreta. Documentar decisiones arquitectónicas relevantes cuando sea necesario.
6. Actualizar pruebas y documentación afectadas, y revisar el diff final para detectar cambios accidentales.
7. Informar qué cambió, cómo se verificó y cualquier limitación pendiente. No hacer commits, publicar ni desplegar salvo que la tarea lo autorice.

<!-- codebase-memory-mcp:start -->
# Codebase Memory

## Codebase Knowledge Graph (codebase-memory-mcp)

This project uses codebase-memory-mcp to maintain a knowledge graph of the codebase.
ALWAYS prefer MCP graph tools over grep/glob/file-search for code discovery.

### Priority Order
1. `search_graph` — find functions, classes, routes, variables by pattern
2. `trace_path` — trace who calls a function or what it calls
3. `get_code_snippet` — read specific function/class source code
4. `check_index_coverage` — validate candidate paths and missed ranges before claims
5. `query_graph` — run Cypher queries for complex patterns
6. `get_architecture` — high-level project summary

### Evidence tiers
- **Scout (Tier 1):** quick positive lookup with few calls and targeted source checks. Mark it provisional; do not make negative or exhaustive claims.
- **Verify (Tier 2, default):** task-directed graph evidence, relevant trace directions, exact snippets for material claims, and relevant pagination.
- **Auditor (Tier 3):** bounded-scope full verification with current generation, complete relevant pagination, both call directions and broader relationships when material, and every limitation disclosed.
- After candidate paths are known in any tier, call `check_index_coverage` once with every evidence path. Add relevant scopes for negative or exhaustive claims. A clean result means no recorded gap, not proof of completeness. For partial, skipped, excluded, stale, pending, or unknown coverage, read/grep the reported ranges or scope before relying on graph results.

### When to fall back to grep/glob
- Searching for string literals, error messages, config values
- Searching non-code files (Dockerfiles, shell scripts, configs)
- When MCP tools return insufficient results

### Examples
- Find a handler: `search_graph(name_pattern=".*OrderHandler.*")`
- Who calls it: `trace_path(function_name="OrderHandler", direction="inbound")`
- Read source: `get_code_snippet(qualified_name="pkg/orders.OrderHandler")`

### Session resets and subagents
- At session start or after compaction, confirm the nearest graph project and generation with `list_projects` or `index_status`, then choose Scout, Verify, or Auditor.
- Before spawning a subagent, query the graph and coverage in the parent. Pass the tier, project, generation/freshness, bounded scope, queries and pagination state, qualified symbols, paths, call-chain findings, coverage evidence with ranges/reasons, source fallback already performed, and unresolved questions in the delegated task context.
- Do not assume subagents inherit MCP access or the parent conversation. If a child lacks MCP tools, it must not call or claim MCP access. It should use the supplied evidence and read/grep exact source, especially every reported missed-coverage range.
<!-- codebase-memory-mcp:end -->
