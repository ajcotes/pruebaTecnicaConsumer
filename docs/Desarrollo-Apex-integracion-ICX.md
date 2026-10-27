# Desarrollo Apex de la integración ICX (Fase C)

Prueba técnica Developer Salesforce · Imagine CX · Autor: Anibal Cortes

Registro de la Fase C del PRD (`PRD-integracion-ICX.md`): construcción del job, sus clases de apoyo, el punto de entrada para la ejecución manual y las clases de prueba. El diagrama de clases está en `Diagrama-de-clases.md` (Mermaid) y `Diagrama-de-clases.png`.

---

## C.1 Clases de la integración (`icx-integration/main/default/classes`)

| Clase | Responsabilidad | Decisiones de diseño |
|---|---|---|
| `ICX_CommerceSyncSettings` | Lee y valida `Commerce_Sync_Setting__mdt`; construye las rutas de las APIs | Objeto de configuración único; valida obligatorios y normaliza lote (1–30) y reintentos (0–5); `testOverride` para pruebas sin depender de la org |
| `ICX_CommerceApiClient` | Único punto con HTTP: Products API y Price Books API | Patrón Gateway: métodos con nombres de negocio; `send` concentra Named Credential, `correlation-id`, reintentos de 429/5xx/timeout y no reintento de 4xx; `findPriceBook` usa `price-book-search` por el hallazgo B.5 |
| `ICX_PriceSyncBatch` | Orquestación: GET producto → crear si 404 o PATCH nombre si cambió → upsert precio; log por producto; SUMMARY | `Batchable` + `AllowsCallouts` + `Stateful`; idempotente por ProductCode; un error por producto no detiene el lote; aborta con SUMMARY si el price book no existe o la configuración está inactiva |
| `ICX_PriceSyncScheduler` | Ejecución programada | `Schedulable`; helpers `schedule(cron)` y `scheduleDaily(hora)` |
| `ICX_PriceSyncInvocable` | Ejecución a demanda | `@InvocableMethod` para Flow, `@AuraEnabled` para Lightning, `jobStatus` para seguimiento |

Todas las clases y métodos llevan cabecera ApexDoc con descripción, autor, parámetros, retorno y excepciones.

## C.2 Punto de entrada para la demo: Screen Flow

`flows/ICX_Sincronizar_Lista_Commerce.flow-meta.xml`, etiqueta "ICX · Sincronizar Lista de precios con Commerce". Tres pasos: pantalla de confirmación → acción Apex `ICX_PriceSyncInvocable` → pantalla con el Id del job y dónde revisar el resultado. Está activo (versión 1) y se puede ejecutar desde Setup › Flows o exponer como acción en una página Lightning.

## C.3 Clases de prueba

| Clase | Qué cubre |
|---|---|
| `ICX_CommerceApiMock` | Simula SCAPI por método y URL: 404 RFC 7807, 201/200 en PUT, búsqueda de price book, 500 permanente por producto, 503 transitorios, `CalloutException`; registra todas las peticiones |
| `ICX_TestDataFactory` | Configuración inyectada y lista de precios con 4 productos: dos válidos, uno con producto inactivo y uno sin código |
| `ICX_PriceSyncBatchTest` (10 métodos) | **CA1** carga inicial crea productos y precios; **CA2** producto nuevo y nombre cambiado; **CA3** re-ejecución sin duplicar y con precio actualizado; exclusión de inactivos y sin código; error en un producto no detiene al resto (con 3 intentos); timeout registrado como excepción; price book inexistente aborta con SUMMARY; error en la búsqueda aborta; configuración inactiva no hace callouts; `run()` devuelve el job |
| `ICX_CommerceApiClientTest` (6) | Cuerpos JSON (catálogo, flags por sitio, id codificado), GET/PUT/PATCH, búsqueda y upsert (201 luego 200), reintentos de transitorios, no reintento de 4xx, agotamiento con 5xx, excepción tras timeouts, helpers de `ApiResponse` |
| `ICX_CommerceSyncSettingsTest` (4) | Carga desde la Custom Metadata real, registro inexistente, validación de faltantes y normalización, `testOverride` |
| `ICX_PriceSyncSchedulerTest` (1) | Cron creado con la expresión correcta y `execute` del Schedulable |
| `ICX_PriceSyncInvocableTest` (2) | Lanzamiento desde Flow, estado del job, captura de error de configuración |

## C.4 Resultado de las pruebas en el sandbox

Comando: `sf apex run test --class-names ICX_CommerceSyncSettingsTest,ICX_CommerceApiClientTest,ICX_PriceSyncBatchTest,ICX_PriceSyncSchedulerTest,ICX_PriceSyncInvocableTest --code-coverage`

| Métrica | Valor |
|---|---|
| Pruebas ejecutadas | 24 |
| Pasaron / fallaron | 24 / 0 |
| Cobertura del conjunto de clases de la integración | 96 % |
| `ICX_CommerceSyncSettings` | 100 % |
| `ICX_CommerceApiClient` | 99 % |
| `ICX_PriceSyncBatch` | 93 % |
| `ICX_PriceSyncScheduler` | 100 % |
| `ICX_PriceSyncInvocable` | 89 % |

Mínimo exigido por la prueba: 75 %. La cobertura global de la org (28 %) es baja por el código preexistente de Italcol y no forma parte del entregable.

## C.5 Despliegue

- 12 clases desplegadas con `sf project deploy start --source-dir icx-integration/main/default/classes --test-level NoTestRun` (12/12).
- Permission set `ICX_Commerce_Sync` actualizado con acceso a las 5 clases (verificado: 5 entradas de `SetupEntityAccess`).
- Flow `ICX_Sincronizar_Lista_Commerce` desplegado y activo.
