# Creación del API Client de B2C Commerce para la integración ICX

Prueba técnica Developer Salesforce · Imagine CX · 26 de octubre de 2026

Este documento registra, paso a paso y con evidencia, la creación del API Client en Salesforce Commerce **Account Manager** que usará el job del CRM para autenticarse contra las Admin APIs (SCAPI) del sandbox `blsb-001`. Es el único cambio hecho hasta ahora fuera del equipo local; nada se ha desplegado en los sandboxes.

## 1. Resultado

| Dato | Valor |
|---|---|
| Account Manager | https://account.demandware.com |
| Organización | Italcol SA (dueña del realm `blsb`) |
| Display name | ICX CRM PriceSync (prueba tecnica) |
| Client ID | `a6fb362f-d807-4377-aef1-5d1392cf56b4` |
| Client Secret | Guardado en `credenciales-commerce-NO-SUBIR.txt`, fuera del repositorio. No se incluye en este documento |
| Tipo | Confidential, habilitado |
| Rol | Salesforce Commerce API con filtro de tenant `blsb_001` (`blsb-001.dx.commercecloud.salesforce.com`) |
| Allowed Scopes | `sfcc.products.rw`, `sfcc.price-books.rw`, `sfcc.catalogs` |
| Token Endpoint Auth Method | `client_secret_post` |
| Creado por | Anibal Cortes (cotesanibal3@gmail.com), 26 oct 2026 21:47 UTC según la auditoría de Account Manager |

## 2. Paso a paso con capturas

### Paso 1. Elegir la organización y el sandbox para el rol Salesforce Commerce API

![Captura 1. Diálogo "Salesforce Commerce API - Filters" dentro de Add API Client](capturas-account-manager/01-tenants-disponibles-italcol-blsb.png)

Qué muestra: al crear el cliente (Add API Client) y agregar el rol **Salesforce Commerce API**, Account Manager pide a qué instancias aplicará ese rol. Al elegir la organización **Italcol SA** aparece el realm `na01.italcolsa.demandware.net (blsb)` con sus instancias: production, staging, development, All Sandboxes y el sandbox `blsb-001.dx.commercecloud.salesforce.com`.

Por qué importa: confirma que el sandbox de la prueba pertenece al realm `blsb` de Italcol SA y que esta cuenta tiene permiso para asignarlo. Se marcó únicamente `blsb-001`, nunca producción ni "All Sandboxes", para que el cliente no tenga alcance sobre otros ambientes.

### Paso 2. Rol asignado con el tenant y sección de scopes

![Captura 2. Rol Salesforce Commerce API con el filtro blsb-001 aplicado, sección JWT vacía e inicio de OpenID Connect](capturas-account-manager/02-formulario-roles-tenant.png)

Qué muestra: el rol **Salesforce Commerce API** ya aparece en el formulario con la etiqueta de filtro `blsb-001.dx.commercecloud.salesforce.com`. La sección **JWT** se dejó vacía porque la autenticación será por client secret, no por llave pública. Debajo empieza la sección **OpenID Connect**, donde se configuran los scopes; en Default Scopes queda el valor por defecto `mail` y en Allowed Scopes comienza `sfcc.products.rw`.

Por qué importa: el token que pida el CRM solo será válido para `blsb_001`. Si en la sustentación preguntan cómo se limita el alcance del cliente, esta captura es la respuesta.

### Paso 3. Scopes permitidos y método de autenticación del token

![Captura 3. Allowed Scopes, Redirect URIs vacío, Token Endpoint Auth Method client_secret_post y botón Save](capturas-account-manager/03-formulario-scopes-auth.png)

Qué muestra: en **Allowed Scopes** se escribieron, uno por línea, `sfcc.products.rw` (crear y actualizar productos), `sfcc.price-books.rw` (crear price books y precios) y `sfcc.catalogs` (leer catálogos). **Redirect URIs** queda vacío porque no hay flujo de usuario. **Token Endpoint Auth Method** se fijó en `client_secret_post`, que es el que piden las Admin APIs de SCAPI. Después de esto se pulsó **Save**.

Por qué importa: estos tres scopes son exactamente los que necesita el job, ni uno más. Las credenciales (Password y Confirm Password, más arriba en el formulario) son el client secret; se generaron en ese momento y se guardaron fuera del repositorio.

### Paso 4. Cliente creado

![Captura 4. Lista de API Clients con el nuevo cliente "ICX CRM PriceSync (prueba tecnica)" en primera fila](capturas-account-manager/04-cliente-creado.png)

Qué muestra: tras guardar, la lista de API Clients incluye el nuevo cliente **ICX CRM PriceSync (prueba tecnica)** con Client ID `a6fb362f-d807-4377-aef1-5d1392cf56b4`, tipo Confidential y estado Enabled. Los tres clientes anteriores (Italcol Staging CLI, ItalcolEcommerce y Sandbox Demo Jennifer) no se tocaron.

Por qué importa: el Client ID es el identificador que se cargará en la External Credential del CRM junto con el secret.

### Paso 5. Detalle y auditoría del cliente

![Captura 5. Detalle del cliente: historial con "API-Client created" y rol Salesforce Commerce API con tenant blsb-001](capturas-account-manager/05-detalle-cliente.png)

Qué muestra: la página de detalle del cliente. En **History** queda el registro de auditoría "API-Client created" con fecha, hora y usuario ejecutor. Abajo se confirma la organización Italcol SA y el rol Salesforce Commerce API con el tenant `blsb-001`.

Por qué importa: es la evidencia de quién creó el cliente y cuándo, útil si Imagine CX pregunta por cambios en su Account Manager.

### Paso 6. Datos del sandbox para las URLs de SCAPI

![Captura 6. Business Manager, Administration › Site Development › Salesforce Commerce API Settings](capturas-account-manager/06-bm-commerce-api-settings.png)

Qué muestra: en Business Manager del sandbox, la página **Salesforce Commerce API Settings** entrega el **Short Code** `eeluxar4` (Status: Active) y el **Organization ID** `f_ecom_blsb_001`.

Por qué importa: con ellos se arma la URL base de todas las llamadas, `https://eeluxar4.api.commercecloud.salesforce.com`, y la ruta `/organizations/f_ecom_blsb_001/...`. El Short Code va en la Named Credential y el Organization ID en la Custom Metadata del CRM.

## 3. Verificación del cliente

Con el Client ID y el secret se pidió un token real a Account Manager:

```
POST https://account.demandware.com/dwsso/oauth2/access_token
grant_type=client_credentials
client_id=a6fb362f-d807-4377-aef1-5d1392cf56b4
client_secret=<secret>
scope=SALESFORCE_COMMERCE_API:blsb_001 sfcc.products.rw sfcc.price-books.rw sfcc.catalogs
```

Respuesta: **HTTP 200**, `token_type` Bearer, `expires_in` 1800 (30 minutos). Scopes devueltos dentro del JWT: `SALESFORCE_COMMERCE_API:blsb_001`, `sfcc.products.rw`, `sfcc.price-books.rw`, `sfcc.catalogs`.

Luego se hicieron tres llamadas de solo lectura a SCAPI Admin con ese token:

| Llamada | Resultado | Lectura |
|---|---|---|
| `GET /product/catalogs/v1/organizations/f_ecom_blsb_001/catalogs` | 200, `total: 0` | Autenticación y scopes correctos. El sandbox no tiene catálogos todavía |
| `GET /product/products/v1/organizations/f_ecom_blsb_001/products/NO-EXISTE-123` | 404 `ProductNotFound` | Comportamiento esperado; es la señal que usará el job para decidir si crea el producto |
| `GET /product/price-books/v1/organizations/f_ecom_blsb_001/price-books` | 404 `Site Not Found` | El listado requiere un sitio y el sandbox aún no tiene ninguno |

## 4. Cómo se usará en el CRM

- **External Credential** `SFCC_Account_Manager`: OAuth 2.0, flujo Client Credentials with Client Secret, URL del proveedor `https://account.demandware.com/dwsso/oauth2/access_token`, scope `SALESFORCE_COMMERCE_API:blsb_001 sfcc.products.rw sfcc.price-books.rw sfcc.catalogs`. El Client ID y el Secret se cargan en el principal, nunca en código.
- **Named Credential** `SFCC_Admin_API`: URL `https://eeluxar4.api.commercecloud.salesforce.com`, autenticada con la External Credential anterior.
- **Permission set** que da acceso al principal al usuario que ejecuta el job.

## 5. Notas

- El secret solo se muestra al crear el cliente. Si se pierde, hay que resetearlo en Account Manager y actualizar el principal en el CRM.
- El cliente es exclusivo de esta integración; no reutiliza los clientes existentes de Italcol.
- El cliente se creó con una ventana de incógnito del navegador y la cuenta `cotesanibal3@gmail.com`, que tiene permisos de administración sobre la organización Italcol SA en Account Manager.
