# PRD · Integración Lista de precios ICX: CRM → B2C Commerce

Prueba técnica Developer Salesforce · Imagine CX

Este documento define qué se va a construir, cómo y en qué orden. Es la guía de ejecución del desarrollo. El orden de los pasos es el orden de ejecución.

---

## 1. Objetivo

Construir un job en el CRM de Salesforce que lleve a B2C Commerce los productos activos de la lista de precios **Lista de precios ICX** con sus precios, de forma idempotente y ejecutable bajo demanda, para que el catálogo y los precios del Commerce estén siempre alineados con el CRM sin digitación manual.

## 2. Alcance

### Dentro del alcance
- Lectura de las entradas activas de la Lista de precios ICX (`PricebookEntry`) cuyo producto esté activo y tenga código.
- Creación del producto en el catálogo maestro de Commerce si no existe; si existe, no se duplica y se actualiza el nombre solo si cambió.
- Creación o actualización del precio del producto en un price book de Commerce (upsert).
- Verificación al inicio de que el price book de destino exista (vía `price-book-search`); el price book se crea y asigna al sitio manualmente en Business Manager, porque el endpoint `PUT /price-books/{id}` responde "Site Not Found" en este sandbox (ver documento de la Fase B).
- Ejecución manual (desde Flow, botón o Execute Anonymous) y programada (Scheduled Apex).
- Registro de cada ejecución y de cada producto en un objeto de log, con manejo de errores por producto y reintentos ante fallas transitorias.
- Clases de prueba con callouts simulados y cobertura mínima del 75 %.
- Configuración manual en Business Manager: sitio, catálogo, categoría, visibilidad, reindex.
- Repositorio con la metadata, el código y la documentación.

### Fuera del alcance (según la prueba)
- Asignación automática de categorías.
- Imágenes, inventario y descripciones extendidas.
- Automatizar la actualización del índice de búsqueda.
- Sincronización Commerce → CRM.
- Eliminación de productos en Commerce cuando se retiran de la lista.
- Despliegue del código del storefront (SFRA). Depende de Imagine CX; ver sección 10.

## 3. Criterios de aceptación

| CA | Escenario | Resultado esperado | Dónde se valida |
|---|---|---|---|
| CA1 | Carga inicial | Todos los productos de la lista ICX quedan en Commerce con precio | Business Manager |
| CA2 | Producto nuevo agregado en vivo | Al correr el job, el producto se crea en Commerce con precio | Business Manager |
| CA3 | Re-ejecución | No se duplican productos; los precios quedan iguales a los del CRM | Business Manager |
| CA4 | Categoría manual | El producto se ve en la tienda en su categoría, con nombre y precio | Tienda en línea (requiere storefront) |

## 4. Restricciones técnicas

- Toda la lógica vive en el CRM, en Apex nativo. Commerce se actualiza por sus Admin APIs (SCAPI).
- Sin middleware ni herramientas externas de integración.
- Ningún endpoint ni credencial en código: Named Credential, External Credential y Custom Metadata.
- Pruebas con `HttpCalloutMock`, cobertura ≥ 75 %.
- Límites de Apex a respetar: 100 callouts por transacción, 120 s por callout, 50.000 registros por batch.

## 5. Arquitectura

```
CRM (Salesforce)                                   B2C Commerce (blsb-001)
─────────────────────────────                      ─────────────────────────────
Pricebook2 "Lista de precios ICX"
  └─ PricebookEntry ──► ICX_PriceSyncBatch ──► SCAPI Admin APIs
                           │                      ├─ Products API  (GET / PUT / PATCH producto)
                           │                      └─ Price Books API (PUT price book, PUT entrada de precio)
                           ├─ ICX_CommerceApiClient (HTTP vía Named Credential SFCC_Admin_API)
                           ├─ ICX_CommerceSyncSettings (Custom Metadata)
                           └─ Commerce_Sync_Log__c (trazabilidad)

Autenticación: External Credential SFCC_Account_Manager
  OAuth 2.0 client credentials → https://account.demandware.com/dwsso/oauth2/access_token
  scope: SALESFORCE_COMMERCE_API:blsb_001 sfcc.products.rw sfcc.price-books.rw sfcc.catalogs
```

Flujo de una ejecución:

1. Lanzar el job (Flow, botón, Execute Anonymous o Scheduler).
2. `start`: cargar configuración, verificar con `price-book-search` que el price book exista en Commerce (si no, abortar con error en el log), consultar las entradas activas de la lista ICX.
3. `execute`, por producto: `GET` producto por `ProductCode`. 404 → `PUT` crear en el catálogo maestro, online y searchable. 200 → `PATCH` nombre solo si cambió. Luego `PUT` upsert del precio.
4. Registrar una fila de log por producto (éxito o error). Un error en un producto no detiene a los demás.
5. `finish`: fila SUMMARY con conteo de exitosos y errores.

## 6. Mapeo de datos

| CRM | B2C Commerce | Regla |
|---|---|---|
| `Product2.ProductCode` | `product.id` y `productId` de la entrada de precio | Llave única en ambos sistemas; base de la idempotencia |
| `Product2.Name` | `product.name.default` | Se crea con el producto; se actualiza si cambia |
| `PricebookEntry.UnitPrice` | `priceTables[0].tiers[0].amount.value`, `quantity: 1` | Upsert en cada ejecución |
| Moneda de la org (COP) | `currencyMnemonic` y `currencyCode` del price book | La org no es multimoneda; se toma de Custom Metadata o de `UserInfo.getDefaultCurrency()` |
| Configuración | `owningCatalogId`, `onlineFlag{site}`, `searchable{site}` | Desde Custom Metadata; las categorías no se tocan |

Filtro de lectura: `Pricebook2.Name = <lista configurada>`, `IsActive = true`, `Product2.IsActive = true`, `Product2.ProductCode != null`.

## 7. Componentes a construir

### 7.1 Metadata (ya creada en `icx-integration`)
| Componente | Tipo | Propósito |
|---|---|---|
| `Commerce_Sync_Setting__mdt` + registro `Default` | Custom Metadata | organizationId, siteId, catalogId, priceBookId, nombre de la lista en CRM, moneda, named credential, tamaño de lote, reintentos, activo |
| `Commerce_Sync_Log__c` | Objeto | Una fila por producto y ejecución, más una fila SUMMARY |
| `SFCC_Account_Manager` | External Credential | OAuth client credentials contra Account Manager |
| `SFCC_Admin_API` | Named Credential | `https://eeluxar4.api.commercecloud.salesforce.com` |
| `ICX_Commerce_Sync` | Permission set | Acceso al principal de la credencial, al log y a las clases |
| Tab del log | Tab | Para revisar ejecuciones en la UI |

### 7.2 Apex
| Clase | Responsabilidad |
|---|---|
| `ICX_CommerceSyncSettings` | Lee y valida la Custom Metadata; expone rutas base |
| `ICX_CommerceApiClient` | Callouts a Products y Price Books (GET/PUT/PATCH producto, búsqueda de price book, PUT de entrada de precio); reintentos ante 429/5xx/timeout; parseo de errores RFC 7807; header `correlation-id` |
| `ICX_PriceSyncBatch` | `Batchable` + `AllowsCallouts` + `Stateful`; lógica por producto; log; resumen |
| `ICX_PriceSyncScheduler` | `Schedulable` para ejecución programada |
| `ICX_PriceSyncInvocable` | `@InvocableMethod` para Flow y `@AuraEnabled` para botón/LWC |

### 7.3 Pruebas
| Clase | Cubre |
|---|---|
| `ICX_CommerceApiMock` | `HttpCalloutMock` que enruta por método y URL: 404/200 en GET producto, 201/200 en PUT, 500 configurable, price book existente o no |
| `ICX_PriceSyncBatchTest` | CA1 (crea productos y precios), CA2 (producto nuevo), CA3 (re-ejecución sin duplicar, PATCH solo si cambia el nombre), price book inexistente (aborta con log), error por producto sin detener el batch, reintento exitoso, exclusión de inactivos y sin código |
| `ICX_CommerceApiClientTest` | Cuerpos JSON, codificación de IDs, reintentos, `errorDetail` |
| `ICX_PriceSyncSchedulerTest`, `ICX_PriceSyncInvocableTest` | Programación y lanzamiento |
| `ICX_CommerceSyncSettingsTest` | Validación de configuración incompleta |

### 7.4 Punto de entrada para la ejecución manual
- Screen Flow "Sincronizar Lista ICX con Commerce" que invoca `ICX_PriceSyncInvocable` y muestra el Id del job, expuesto como acción en la página del Pricebook2 o en la app.

## 8. Manejo de errores

- **Por producto:** cualquier fallo (HTTP 4xx/5xx, excepción, timeout) se registra en `Commerce_Sync_Log__c` con operación, código HTTP, correlation-id y mensaje; el batch continúa con el siguiente.
- **Reintentos:** 429 y 5xx y `CalloutException` se reintentan hasta el máximo configurado; 4xx no se reintenta porque es error de datos o permisos.
- **Fatal:** si la configuración está incompleta o el price book no existe en Commerce, el job aborta y deja una fila SUMMARY con el motivo.
- **Idempotencia como recuperación:** la siguiente ejecución repara lo que quedó pendiente, sin duplicar.
- **Si Commerce no responde a mitad de la carga:** los productos ya procesados quedan con precio; los que fallaron quedan en el log como ERROR; al correr de nuevo se completan. En producción se agregarían alertas sobre el log, backoff exponencial, campo de última sincronización en `PricebookEntry` para procesar solo cambios, y Platform Event o email con el resumen.

## 9. Pasos de ejecución

### Fase A · Preparar el sandbox de Commerce (Business Manager)
1. Importar "Storefront Reference Architecture Demo Sites" desde Site Import & Export, o crear a mano un sitio y un catálogo maestro.
2. Identificar el ID del catálogo maestro y el ID del sitio.
3. Confirmar que COP esté entre las monedas permitidas del sitio.
4. Crear el price book `icx-cop-list-prices` en COP y asignarlo al sitio.
5. Anotar catálogo, sitio y price book en la Custom Metadata `Default`.

### Fase B · Configurar el CRM
5. Desplegar la metadata de `icx-integration`: Custom Metadata, objeto de log, External Credential, Named Credential, permission set y tab.
6. Cargar el Client ID y el Client Secret en el principal `ICX_Integration` de la External Credential.
7. Asignar el permission set `ICX_Commerce_Sync` al usuario que ejecutará el job.
8. Probar la credencial con un `GET` de producto desde Execute Anonymous.

### Fase C · Desarrollar
9. Escribir `ICX_CommerceSyncSettings` y su prueba.
10. Escribir `ICX_CommerceApiClient` con el mock y sus pruebas.
11. Escribir `ICX_PriceSyncBatch` con las pruebas de CA1, CA2, CA3 y errores.
12. Escribir `ICX_PriceSyncScheduler` e `ICX_PriceSyncInvocable` con sus pruebas.
13. Crear el Screen Flow y la acción para lanzar el job.
14. Desplegar al sandbox y ejecutar todas las pruebas; verificar cobertura ≥ 75 %.

### Fase D · Datos de prueba en el CRM
15. Verificar los productos de la Lista de precios ICX: activos y con `ProductCode`.
16. Si la lista no tiene los 4 productos de la prueba, agregar productos propios de ejemplo sin tocar los existentes.

### Fase E · Ejecutar y validar
17. Correr el job y validar CA1 en Business Manager: productos en el catálogo maestro y precios en el price book.
18. Agregar un producto a la lista, correr el job y validar CA2.
19. Cambiar un precio, correr el job dos veces y validar CA3: sin duplicados, precio actualizado.
20. Asignar categoría, marcar online y searchable, reindexar y validar CA4 en la tienda si hay storefront; si no, en Business Manager.
21. Dejar el job programado con `ICX_PriceSyncScheduler`.

### Fase F · Entrega
22. Actualizar el README con setup, mapeo, cómo ejecutar y cómo probar.
23. Subir código y metadata al repositorio.

## 10. Dependencias externas y riesgos

| Dependencia / riesgo | Impacto | Mitigación |
|---|---|---|
| Storefront (SFRA) no desplegado en `blsb-001` | CA4 no se puede mostrar en la tienda | Solicitado a Imagine CX; alternativa: validar CA4 en Business Manager |
| Lista ICX con 2 productos (uno inactivo) en lugar de 4 | Demo de CA1 con menos productos | Agregar productos propios activos; el inactivo se excluye por diseño |
| Flujo client credentials de la External Credential con Account Manager | Si no negocia el token, el job no autentica | Plan B: pedir el token desde Apex con Named Credential de usuario/contraseña |
| Sesión de Business Manager caduca rápido | Interrupciones al configurar | Trabajar por bloques cortos |
| Límite de callouts por transacción | Lotes grandes fallarían | Tamaño de lote 20 (máx. 3 callouts por producto) |
