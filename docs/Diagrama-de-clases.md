# Diagrama de clases · Integración Lista de precios ICX (CRM → B2C Commerce)

Prueba técnica Developer Salesforce · Imagine CX · Autor: Anibal Cortes

El diagrama muestra las cinco clases de la integración (paquete `icx-integration`), los puntos de entrada, el objeto de log, la Custom Metadata y las clases de prueba. Las flechas indican quién usa a quién.

```mermaid
classDiagram
    direction TB

    class Commerce_Sync_Setting__mdt {
        <<Custom Metadata>>
        Organization_Id__c
        Site_Id__c
        Catalog_Id__c
        Price_Book_Id__c
        CRM_Pricebook_Name__c
        Currency_Code__c
        Named_Credential__c
        Batch_Size__c
        Max_Retries__c
        Active__c
    }

    class Commerce_Sync_Log__c {
        <<Custom Object>>
        Run_Id__c
        Product_Code__c
        Product_Name__c
        Unit_Price__c
        Currency_Code__c
        Status__c
        Operation__c
        HTTP_Status__c
        Correlation_Id__c
        Message__c
        Success_Count__c
        Error_Count__c
    }

    class ICX_CommerceSyncSettings {
        +String organizationId
        +String siteId
        +String catalogId
        +String priceBookId
        +String crmPricebookName
        +String currencyCode
        +String namedCredential
        +Integer batchSize
        +Integer maxRetries
        +Boolean active
        +load(devName) ICX_CommerceSyncSettings$
        +validate()
        +hasSite() Boolean
        +calloutBase() String
        +productsPath() String
        +priceBooksBase() String
    }

    class ICX_CommerceApiClient {
        -ICX_CommerceSyncSettings cfg
        +getProduct(productId) ApiResponse
        +createProduct(productId, name) ApiResponse
        +updateProductName(productId, name) ApiResponse
        +findPriceBook() ApiResponse
        +upsertPrice(productId, price, currency) ApiResponse
        +productNameFrom(res) String$
        +priceBookFound(res) Boolean$
        -send(method, path, body) ApiResponse
    }

    class ApiResponse {
        +Integer statusCode
        +String body
        +String correlationId
        +String method
        +String path
        +Integer attempts
        +isSuccess() Boolean
        +isNotFound() Boolean
        +errorDetail() String
        +bodyAsMap() Map
    }

    class ICX_PriceSyncBatch {
        <<Batchable AllowsCallouts Stateful>>
        -ICX_CommerceSyncSettings cfg
        -ICX_CommerceApiClient client
        -String runId
        -Integer successCount
        -Integer errorCount
        -String fatalError
        +run() Id$
        +start(bc) QueryLocator
        +execute(bc, scope)
        +finish(bc)
        -processEntry(pbe) Commerce_Sync_Log__c
        -verifyPriceBook()
        -buildQuery() String
    }

    class ICX_PriceSyncScheduler {
        <<Schedulable>>
        +execute(sc)
        +schedule(jobName, cron) Id$
        +scheduleDaily(hour) Id$
    }

    class ICX_PriceSyncInvocable {
        +launchFromFlow(inputs) List$
        +launch() String$
        +jobStatus(jobId) Map$
    }

    class Flow_ICX_Sincronizar {
        <<Screen Flow>>
        pantallaConfirmar
        accionLanzarJob
        pantallaResultado
    }

    class SFCC_Admin_API {
        <<Named Credential>>
        url_eeluxar4_api_commercecloud
        externalCredential_SFCC_Account_Manager
    }

    Flow_ICX_Sincronizar --> ICX_PriceSyncInvocable : acción invocable
    ICX_PriceSyncScheduler --> ICX_PriceSyncBatch : run()
    ICX_PriceSyncInvocable --> ICX_PriceSyncBatch : run()
    ICX_PriceSyncBatch --> ICX_CommerceSyncSettings : load()
    ICX_PriceSyncBatch --> ICX_CommerceApiClient : usa
    ICX_PriceSyncBatch --> Commerce_Sync_Log__c : inserta
    ICX_CommerceSyncSettings ..> Commerce_Sync_Setting__mdt : lee
    ICX_CommerceApiClient --> ICX_CommerceSyncSettings : rutas y IDs
    ICX_CommerceApiClient *-- ApiResponse : devuelve
    ICX_CommerceApiClient ..> SFCC_Admin_API : callout
```

## Clases de prueba

```mermaid
classDiagram
    direction LR
    class ICX_CommerceApiMock {
        <<HttpCalloutMock>>
        +Map existingProducts
        +Boolean priceBookExists
        +Set failPriceFor
        +Integer transientPriceFailures
        +Boolean throwOnGet
        +List requests
        +respond(req) HttpResponse
        +count(prefix) Integer
    }
    class ICX_TestDataFactory {
        +settings() ICX_CommerceSyncSettings$
        +createPriceList() Pricebook2$
    }
    class ICX_PriceSyncBatchTest
    class ICX_CommerceApiClientTest
    class ICX_CommerceSyncSettingsTest
    class ICX_PriceSyncSchedulerTest
    class ICX_PriceSyncInvocableTest

    ICX_PriceSyncBatchTest --> ICX_CommerceApiMock
    ICX_PriceSyncBatchTest --> ICX_TestDataFactory
    ICX_CommerceApiClientTest --> ICX_CommerceApiMock
    ICX_CommerceApiClientTest --> ICX_TestDataFactory
    ICX_CommerceSyncSettingsTest --> ICX_TestDataFactory
    ICX_PriceSyncSchedulerTest --> ICX_CommerceApiMock
    ICX_PriceSyncInvocableTest --> ICX_CommerceApiMock
```

## Responsabilidad de cada clase

| Clase | Capa | Responsabilidad |
|---|---|---|
| `ICX_PriceSyncInvocable` | Entrada | Lanzar el job desde Flow, Lightning o Execute Anonymous y consultar su estado |
| `ICX_PriceSyncScheduler` | Entrada | Ejecución programada (cron) |
| `ICX_PriceSyncBatch` | Orquestación | Regla de negocio por producto: GET → crear o actualizar nombre → upsert precio; log y resumen |
| `ICX_CommerceApiClient` | Acceso externo | Único punto con HTTP: Products API y Price Books API, reintentos y errores |
| `ICX_CommerceSyncSettings` | Configuración | Lee y valida la Custom Metadata; construye rutas |
| `ICX_CommerceApiMock` | Pruebas | Simula Commerce por método y URL |
| `ICX_TestDataFactory` | Pruebas | Configuración inyectada y lista de precios de prueba |
