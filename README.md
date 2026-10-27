# Integración Lista de precios ICX · CRM → B2C Commerce

Prueba técnica Developer Salesforce · Imagine CX · Autor: Anibal Cortes

Job Apex nativo que lleva los productos activos de la **Lista de precios ICX** (`Pricebook2`) del CRM a **Salesforce B2C Commerce Cloud** a través de sus Admin APIs (SCAPI): crea el producto si no existe, actualiza el nombre si cambió y escribe el precio en un price book del Commerce. Es idempotente (correrlo varias veces no duplica), se ejecuta a demanda desde un Flow o programado, y deja un log por producto y por ejecución. Sin middleware, sin credenciales en código.

## Resultado

| Criterio | Estado | Evidencia |
|---|---|---|
| CA1 Carga inicial | Cumplido | 4 productos creados con precio en una ejecución (4 s, 0 errores) |
| CA2 Producto nuevo en vivo | Cumplido | Producto agregado a la lista y creado en Commerce en la siguiente ejecución |
| CA3 Sin duplicados | Cumplido | Re-ejecuciones sin crear productos; precio cambiado en el CRM actualizado en Commerce |
| CA4 Producto en la tienda | Cumplido | Productos en su categoría con nombre y precio en pesos en la tienda `ICX` |
| Cobertura de pruebas | 96 % | 25 pruebas Apex con Commerce simulado (mínimo exigido: 75 %) |
| Job programado | Hecho | Diario a las 02:00 (`ICX_PriceSyncScheduler`) |

Detalle con capturas en [`docs/Pruebas-funcionales-integracion-ICX.pdf`](docs/Pruebas-funcionales-integracion-ICX.pdf).

## Arquitectura

```
CRM (Salesforce)                                      B2C Commerce (sandbox blsb-001)
──────────────────────────────                        ───────────────────────────────────
Flow / Scheduler / Execute Anonymous
        │
        ▼
ICX_PriceSyncInvocable ──► ICX_PriceSyncBatch ──► ICX_CommerceApiClient ──► Named Credential ──► SCAPI Admin
                                  │                        │                SFCC_Admin_API         ├─ Products API
                                  ▼                        ▼                (External Credential   └─ Price Books API
                        Commerce_Sync_Log__c    ICX_CommerceSyncSettings     OAuth client credentials
                                                (Commerce_Sync_Setting__mdt)  contra Account Manager)
```

| Clase | Responsabilidad |
|---|---|
| `ICX_CommerceSyncSettings` | Lee y valida la Custom Metadata `Commerce_Sync_Setting__mdt` (organización, sitio, catálogo, price book, lista del CRM, moneda, named credential, lote, reintentos) |
| `ICX_CommerceApiClient` | Único punto con HTTP. Products API (GET/PUT/PATCH) y Price Books API (búsqueda y upsert de precio). Reintentos ante 429/5xx/timeout, no ante 4xx. Header `correlation-id` |
| `ICX_PriceSyncBatch` | `Batchable` + `AllowsCallouts` + `Stateful`. Por producto: GET → crear si 404, PATCH nombre si cambió, PATCH visibilidad si falta → upsert precio. Log por producto y fila SUMMARY |
| `ICX_PriceSyncScheduler` | Ejecución programada (`scheduleDaily(hora)` o cron) |
| `ICX_PriceSyncInvocable` | `@InvocableMethod` para el Flow, `@AuraEnabled` para Lightning, consulta de estado del job |

Diagrama completo: [`docs/Diagrama-de-clases.md`](docs/Diagrama-de-clases.md) · [`docs/Diagrama-de-clases.png`](docs/Diagrama-de-clases.png)

### Mapeo de campos

| CRM | B2C Commerce | Regla |
|---|---|---|
| `Product2.ProductCode` | `product.id` y `productId` de la entrada de precio | Llave única en ambos sistemas; base de la idempotencia |
| `Product2.Name` | `product.name.default` | Se crea con el producto; PATCH solo si cambia |
| `PricebookEntry.UnitPrice` | `priceTables[0].tiers[0].amount.value`, cantidad 1 | Upsert en cada ejecución |
| Moneda de la org (COP) | `currencyMnemonic` y moneda del price book | Debe coincidir con una moneda permitida del sitio |
| Custom Metadata | `owningCatalogId`, `onlineFlag{site}`, `searchable{site}` | Las categorías no se tocan: se asignan a mano en Business Manager |

Filtro de lectura: entradas activas de la lista configurada cuyo producto esté activo y tenga `ProductCode`.

### Manejo de errores

- Cada producto es independiente: un fallo (HTTP 4xx/5xx, timeout, excepción) se registra en `Commerce_Sync_Log__c` con operación, código HTTP, correlation-id y mensaje, y el batch sigue con el siguiente.
- 429, 5xx y `CalloutException` se reintentan hasta `Max_Retries__c`; 4xx no, porque son errores de datos o permisos.
- Si la configuración está incompleta o el price book no existe en Commerce, el job aborta sin procesar productos y deja una fila SUMMARY con el motivo.
- Si Commerce cae a mitad de la carga, los productos procesados quedan con precio, los que fallaron quedan en ERROR y la siguiente ejecución los completa: la idempotencia es la estrategia de recuperación.
- Producción: backoff exponencial, alertas sobre el log, campo de última sincronización en `PricebookEntry` para procesar solo cambios, resumen por email o Platform Event.

## Estructura del repositorio

```
icx-integration/main/default/   ← entregable (package directory propio)
  classes/                      5 clases + 7 de prueba/apoyo, con ApexDoc
  objects/Commerce_Sync_Setting__mdt   Custom Metadata de configuración
  objects/Commerce_Sync_Log__c         Objeto de log (+ vista "Todos los logs")
  customMetadata/               Registro Default
  externalCredentials/          SFCC_Account_Manager (OAuth client credentials)
  namedCredentials/             SFCC_Admin_API
  permissionsets/               ICX_Commerce_Sync
  flows/                        ICX_Sincronizar_Lista_Commerce (Screen Flow)
  tabs/                         Commerce Sync Logs
docs/                           PRD, análisis, configuración por fases, pruebas, diagrama, capturas
scripts/apex/                   Scripts de ejecución y de prueba (ver abajo)
```

`force-app/` contiene metadata preexistente de la org y no forma parte de la entrega.

## Despliegue y configuración

Requisitos: Salesforce CLI, acceso al sandbox CRM y un API client de Account Manager con rol *Salesforce Commerce API* para el tenant y scopes `sfcc.products.rw`, `sfcc.price-books.rw`, `sfcc.catalogs` (cómo se creó: [`docs/Creacion-API-Client-Commerce.pdf`](docs/Creacion-API-Client-Commerce.pdf)).

1. **Commerce (Business Manager)**, una sola vez: catálogo maestro (`icx-master-catalog`), price book en la moneda del CRM (`icx-cop-list-prices`) asignado al sitio, y la moneda habilitada en el sitio. El job verifica que el price book exista; no lo crea. Detalle: [`docs/Configuracion-Commerce-sitio-demo-SFRA.pdf`](docs/Configuracion-Commerce-sitio-demo-SFRA.pdf).
2. **Desplegar la metadata** (en sandbox, sin ejecutar las pruebas de la org):
   ```
   sf project deploy start --source-dir icx-integration -o <alias> --test-level NoTestRun
   ```
3. **Credenciales**: Setup › Named Credentials › External Credentials › *SFCC Account Manager* › principal `ICX_Integration` › Modificar: Client ID y Client Secret del API client. Es el único secreto y nunca va en código ni en el repositorio.
4. **Permiso**: asignar el permission set `ICX_Commerce_Sync` al usuario que ejecuta el job.
   ```
   sf org assign permset -n ICX_Commerce_Sync -o <alias>
   ```
5. **Configuración**: revisar el registro `Default` de `Commerce_Sync_Setting__mdt` (organización, sitio, catálogo, price book, nombre de la lista, moneda, lote, reintentos). Valores actuales: `f_ecom_blsb_001`, `ICX`, `icx-master-catalog`, `icx-cop-list-prices`, "Lista de precios ICX", `COP`, 20, 2.
6. **Probar la conexión**: `sf apex run -f scripts/apex/icx-test-conexion-commerce.apex -o <alias>` (tres GET reales a Commerce).

Detalle: [`docs/Configuracion-CRM-credenciales-y-metadata.pdf`](docs/Configuracion-CRM-credenciales-y-metadata.pdf).

## Ejecución

| Forma | Cómo |
|---|---|
| Interfaz | Flow **ICX · Sincronizar Lista de precios con Commerce** (`/flow/ICX_Sincronizar_Lista_Commerce`): confirma, lanza el job y muestra su Id |
| Terminal | `sf apex run -f scripts/apex/icx-ejecutar-job.apex -o <alias>` |
| Apex | `ICX_PriceSyncBatch.run();` o `ICX_PriceSyncInvocable.launch();` |
| Programado | `sf apex run -f scripts/apex/icx-programar-job.apex -o <alias>` (diario 02:00) o `ICX_PriceSyncScheduler.schedule('nombre', '<cron>')` |

Resultado: pestaña **Commerce Sync Logs**, vista "Todos los logs": una fila por producto (`SUCCESS`/`ERROR`, operación, HTTP, precio) y una fila `SUMMARY` por ejecución con totales y duración.

Después del job, en Business Manager: asignar los productos a una categoría del catálogo de la tienda, marcar online y buscable si hace falta (el job ya lo hace para el sitio configurado) y reconstruir el índice de búsqueda.

## Pruebas

```
sf apex run test -o <alias> --code-coverage \
  --class-names ICX_CommerceSyncSettingsTest,ICX_CommerceApiClientTest,ICX_PriceSyncBatchTest,ICX_PriceSyncSchedulerTest,ICX_PriceSyncInvocableTest
```

`ICX_CommerceApiMock` simula SCAPI por método y URL (404 RFC 7807, 201/200, búsqueda de price book, 500 fijo, 503 transitorios, timeout). `ICX_PriceSyncBatchTest` cubre CA1, CA2, CA3, exclusión de inactivos y sin código, visibilidad por sitio, error por producto sin detener el batch, reintentos, price book inexistente y configuración inactiva. Resultado en el sandbox: 25/25, 96 % sobre las clases de la integración.

Scripts de apoyo para la demo: `icx-datos-ejemplo-lista-icx.apex` (productos de ejemplo), `icx-ca2-producto-nuevo.apex`, `icx-ca3-cambiar-precio.apex`.

## Decisiones técnicas y hallazgos

- **SCAPI Admin en lugar de OCAPI**: OCAPI está deprecada desde abril de 2026 y su Data API no tiene recurso de price books.
- **Price book verificado, no creado**: en este sandbox `GET`/`PUT /price-books/{id}` responde `Site Not Found` incluso para price books existentes; `price-book-search` y `price-book-entries` funcionan. El job usa la búsqueda para verificar y el endpoint de entradas para escribir.
- **PUT de producto solo al crear**: el PUT sobrescribe el documento completo y borraría la categoría asignada a mano; para existentes se usa PATCH (nombre y flags de sitio).
- **Sitio `ICX` en COP**: SFRA fuerza la moneda de la sesión según el idioma (`countries.json`) y no incluye COP, por lo que en el sitio de demo RefArch los precios en pesos no se mostraban. Se creó un sitio con moneda por defecto COP, mismas cartridges y mismo catálogo de tienda; sin modificar código del storefront.
- **Storefront**: el sandbox llegó vacío; la importación "Storefront Reference Architecture Demo Sites" de Business Manager instala los datos y el código de SFRA.
- **Despliegues bloqueados por clases ajenas**: dos clases obsoletas de la org no compilaban y Salesforce rechazaba cualquier despliegue; se dejaron como stubs con la misma firma (respaldo del original fuera del repositorio).

## Documentación

| Documento | Contenido |
|---|---|
| [`docs/PRD-integracion-ICX.md`](docs/PRD-integracion-ICX.md) | Alcance, arquitectura, componentes y pasos de ejecución |
| [`docs/Analisis-sesion-integracion-ICX.pdf`](docs/Analisis-sesion-integracion-ICX.pdf) | Análisis de la prueba y validación de APIs y sandboxes |
| [`docs/Creacion-API-Client-Commerce.pdf`](docs/Creacion-API-Client-Commerce.pdf) | API client en Account Manager, paso a paso |
| [`docs/Configuracion-Commerce-sitio-demo-SFRA.pdf`](docs/Configuracion-Commerce-sitio-demo-SFRA.pdf) | Fase A: demo SFRA, catálogo, price book, moneda |
| [`docs/Configuracion-CRM-credenciales-y-metadata.pdf`](docs/Configuracion-CRM-credenciales-y-metadata.pdf) | Fase B: desbloqueo, despliegue, credenciales, conexión |
| [`docs/Desarrollo-Apex-integracion-ICX.pdf`](docs/Desarrollo-Apex-integracion-ICX.pdf) | Fase C: clases, pruebas, Flow |
| [`docs/Pruebas-funcionales-integracion-ICX.pdf`](docs/Pruebas-funcionales-integracion-ICX.pdf) | Fases D y E: CA1 a CA4 con capturas, sitio ICX, job programado |
| [`docs/Diagrama-de-clases.md`](docs/Diagrama-de-clases.md) | Diagrama de clases (Mermaid y PNG) |
| [`docs/HU_Prueba_Tecnica_Developer_Salesforce.pdf`](docs/HU_Prueba_Tecnica_Developer_Salesforce.pdf) | Enunciado de la prueba |
