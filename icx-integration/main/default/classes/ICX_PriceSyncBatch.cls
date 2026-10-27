/**
 * @description Job de sincronización CRM → B2C Commerce. Por cada PricebookEntry activa de la
 *              "Lista de precios ICX" cuyo producto esté activo y tenga código:
 *                1. GET del producto en Commerce por ProductCode.
 *                2. 404 → PUT para crearlo en el catálogo maestro. 200 → PATCH del nombre solo si cambió.
 *                   Nunca duplica: el ProductCode es la llave en ambos sistemas.
 *                3. PUT upsert del precio en el price book. Es idempotente: correr N veces deja el mismo resultado.
 *              Cada producto deja una fila en Commerce_Sync_Log__c; un fallo en uno no detiene a los demás.
 *              Al terminar se escribe una fila SUMMARY con los totales. Implementa Batchable con callouts
 *              y Stateful para conservar los contadores entre lotes.
 * @author Anibal Cortes | 10-26-2026
 */
public with sharing class ICX_PriceSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    public static final String STATUS_SUCCESS = 'SUCCESS';
    public static final String STATUS_ERROR = 'ERROR';
    public static final String STATUS_SUMMARY = 'SUMMARY';

    private final String settingsName;
    private ICX_CommerceSyncSettings cfg;
    private ICX_CommerceApiClient client;

    @TestVisible private String runId;
    @TestVisible private Integer successCount = 0;
    @TestVisible private Integer errorCount = 0;
    @TestVisible private String fatalError;
    @TestVisible private Datetime startedAt;

    /**
     * @description Construye el job con la configuración "Default".
     * @author Anibal Cortes | 10-26-2026
     **/
    public ICX_PriceSyncBatch() {
        this(ICX_CommerceSyncSettings.DEFAULT_RECORD);
    }

    /**
     * @description Construye el job con un registro de configuración específico (permite varias listas o entornos).
     * @author Anibal Cortes | 10-26-2026
     * @param settingsName Developer name del registro de Commerce_Sync_Setting__mdt.
     **/
    public ICX_PriceSyncBatch(String settingsName) {
        this.settingsName = settingsName;
    }

    /**
     * @description Lanza el job con la configuración "Default" y el tamaño de lote configurado.
     *              Es el método que usan el Flow, el Scheduler y Execute Anonymous.
     * @author Anibal Cortes | 10-26-2026
     * @return Id Id del AsyncApexJob encolado.
     * @throws ICX_CommerceSyncSettings.SettingsException Si la configuración no existe o está incompleta.
     **/
    public static Id run() {
        ICX_CommerceSyncSettings s = ICX_CommerceSyncSettings.load(ICX_CommerceSyncSettings.DEFAULT_RECORD);
        return Database.executeBatch(new ICX_PriceSyncBatch(s.developerName), s.batchSize);
    }

    /**
     * @description Inicio del batch. Genera el runId, carga la configuración, verifica que esté activa y que
     *              el price book exista en Commerce, y devuelve las entradas a procesar. Si algo de eso falla,
     *              guarda el motivo en fatalError y devuelve una consulta vacía para que el job termine con
     *              una fila SUMMARY explicando el aborto, sin procesar productos.
     * @author Anibal Cortes | 10-26-2026
     * @param bc Contexto del batch.
     * @return Database.QueryLocator Entradas activas de la lista con producto activo y con ProductCode.
     **/
    public Database.QueryLocator start(Database.BatchableContext bc) {
        startedAt = Datetime.now();
        runId = 'RUN-' + startedAt.formatGmt('yyyyMMdd-HHmmss') + '-' + String.valueOf(bc.getJobId()).right(6);
        try {
            cfg = ICX_CommerceSyncSettings.load(settingsName);
            client = new ICX_CommerceApiClient(cfg);
            if (!cfg.active) {
                fatalError = 'La configuración "' + settingsName + '" está inactiva (Active__c = false).';
            } else {
                verifyPriceBook();
            }
        } catch (Exception e) {
            fatalError = e.getTypeName() + ': ' + e.getMessage();
        }
        if (fatalError != null) {
            return Database.getQueryLocator([SELECT Id FROM PricebookEntry WHERE Id = null]);
        }
        return Database.getQueryLocator(buildQuery());
    }

    /**
     * @description Procesa un lote de entradas: hace los callouts de cada producto y al final inserta todas
     *              las filas de log del lote en un solo DML (los callouts siempre van antes del DML).
     * @author Anibal Cortes | 10-26-2026
     * @param bc Contexto del batch.
     * @param scope Entradas de la lista de precios de este lote.
     **/
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (cfg == null) {
            cfg = ICX_CommerceSyncSettings.load(settingsName);
            client = new ICX_CommerceApiClient(cfg);
        }
        List<Commerce_Sync_Log__c> logs = new List<Commerce_Sync_Log__c>();
        for (SObject so : scope) {
            logs.add(processEntry((PricebookEntry) so));
        }
        insert logs; // DML después de todos los callouts del lote
    }

    /**
     * @description Cierre del batch: inserta la fila SUMMARY con exitosos, errores, duración y, si aplica, el error fatal.
     * @author Anibal Cortes | 10-26-2026
     * @param bc Contexto del batch.
     **/
    public void finish(Database.BatchableContext bc) {
        insert new Commerce_Sync_Log__c(
            Run_Id__c = runId,
            Status__c = STATUS_SUMMARY,
            Operation__c = fatalError == null ? 'Ejecución finalizada' : 'Ejecución abortada',
            Success_Count__c = successCount,
            Error_Count__c = errorCount,
            Message__c = buildSummaryMessage(bc)
        );
    }

    // ---------------- lógica por producto

    /**
     * @description Aplica la regla de negocio a una entrada de precio y devuelve su fila de log (sin insertar):
     *              GET producto → crear si no existe o actualizar nombre si cambió → upsert del precio.
     *              Cualquier respuesta no exitosa o excepción se captura y se registra como ERROR; el
     *              batch continúa con el siguiente producto.
     * @author Anibal Cortes | 10-26-2026
     * @param pbe Entrada de precio con Product2.ProductCode, Product2.Name y UnitPrice.
     * @return Commerce_Sync_Log__c Fila de log con estado SUCCESS o ERROR y el detalle de la operación.
     **/
    @TestVisible
    private Commerce_Sync_Log__c processEntry(PricebookEntry pbe) {
        String productCode = pbe.Product2.ProductCode;
        String productName = pbe.Product2.Name;
        String currencyCode = resolveCurrency(pbe);
        Commerce_Sync_Log__c log = new Commerce_Sync_Log__c(
            Run_Id__c = runId,
            Pricebook_Entry_Id__c = pbe.Id,
            Product_Code__c = productCode,
            Product_Name__c = productName,
            Unit_Price__c = pbe.UnitPrice,
            Currency_Code__c = currencyCode
        );
        List<String> ops = new List<String>();
        try {
            // 1. ¿Existe el producto en Commerce?
            ICX_CommerceApiClient.ApiResponse getRes = client.getProduct(productCode);
            if (getRes.isNotFound()) {
                // 2a. No existe: crear
                ICX_CommerceApiClient.ApiResponse createRes = client.createProduct(productCode, productName);
                if (!createRes.isSuccess()) {
                    return fail(log, 'crear producto', createRes);
                }
                ops.add('producto creado');
            } else if (getRes.isSuccess()) {
                // 2b. Ya existe: no duplicar; actualizar el nombre solo si cambió
                String remoteName = ICX_CommerceApiClient.productNameFrom(getRes);
                if (remoteName != productName) {
                    ICX_CommerceApiClient.ApiResponse patchRes = client.updateProductName(productCode, productName);
                    if (!patchRes.isSuccess()) {
                        return fail(log, 'actualizar nombre', patchRes);
                    }
                    ops.add('nombre actualizado');
                } else {
                    ops.add('producto existente');
                }
            } else {
                return fail(log, 'consultar producto', getRes);
            }
            // 3. Precio (upsert)
            ICX_CommerceApiClient.ApiResponse priceRes = client.upsertPrice(productCode, pbe.UnitPrice, currencyCode);
            if (!priceRes.isSuccess()) {
                return fail(log, 'asignar precio', priceRes);
            }
            ops.add(priceRes.statusCode == 201 ? 'precio creado' : 'precio actualizado');
            log.Status__c = STATUS_SUCCESS;
            log.Operation__c = String.join(ops, ' + ');
            log.HTTP_Status__c = priceRes.statusCode;
            log.Correlation_Id__c = priceRes.correlationId;
            log.Message__c = productCode + ' → ' + cfg.priceBookId + ' = ' + pbe.UnitPrice + ' ' + currencyCode + ' (' + priceRes.attempts + ' intento(s))';
            successCount++;
        } catch (Exception e) {
            log.Status__c = STATUS_ERROR;
            log.Operation__c = ops.isEmpty() ? 'excepción' : String.join(ops, ' + ') + ' + excepción';
            log.Message__c = e.getTypeName() + ': ' + e.getMessage();
            errorCount++;
        }
        return log;
    }

    /**
     * @description Marca la fila de log como ERROR con la operación que falló, el código HTTP, el
     *              correlation-id y el detalle del error, e incrementa el contador de errores.
     * @author Anibal Cortes | 10-26-2026
     * @param log Fila de log del producto.
     * @param operation Operación que falló (crear producto, actualizar nombre, asignar precio, consultar producto).
     * @param res Respuesta no exitosa que causó el fallo.
     * @return Commerce_Sync_Log__c La misma fila, completada.
     **/
    private Commerce_Sync_Log__c fail(Commerce_Sync_Log__c log, String operation, ICX_CommerceApiClient.ApiResponse res) {
        log.Status__c = STATUS_ERROR;
        log.Operation__c = operation;
        log.HTTP_Status__c = res.statusCode;
        log.Correlation_Id__c = res.correlationId;
        log.Message__c = res.method + ' ' + res.path + ' → HTTP ' + res.statusCode + ' (' + res.attempts + ' intento(s)): ' + res.errorDetail();
        errorCount++;
        return log;
    }

    /**
     * @description Verifica con price-book-search que el price book configurado exista. El price book es
     *              configuración y se crea en Business Manager; el job no lo crea porque el endpoint
     *              PUT /price-books/{id} responde "Site Not Found" en el sandbox.
     * @author Anibal Cortes | 10-26-2026
     * @throws ICX_CommerceApiClient.CommerceApiException Si la búsqueda falla o el price book no existe
     *         (el mensaje indica cómo crearlo).
     **/
    @TestVisible
    private void verifyPriceBook() {
        ICX_CommerceApiClient.ApiResponse res = client.findPriceBook();
        if (!res.isSuccess()) {
            throw new ICX_CommerceApiClient.CommerceApiException('No se pudo consultar el price book "' + cfg.priceBookId + '": HTTP ' + res.statusCode + ' ' + res.errorDetail());
        }
        if (!ICX_CommerceApiClient.priceBookFound(res)) {
            throw new ICX_CommerceApiClient.CommerceApiException('El price book "' + cfg.priceBookId + '" no existe en Commerce. Créalo en Business Manager (Merchant Tools › Products and Catalogs › Price Books) en moneda ' + cfg.currencyCode + ' y asígnalo al sitio ' + cfg.siteId + '.');
        }
    }

    /**
     * @description Arma el SOQL de las entradas a sincronizar: lista configurada, entrada activa, producto
     *              activo y con ProductCode. Agrega CurrencyIsoCode solo si la org es multimoneda.
     * @author Anibal Cortes | 10-26-2026
     * @return String Consulta SOQL ordenada por ProductCode.
     **/
    @TestVisible
    private String buildQuery() {
        String fields = 'Id, UnitPrice, IsActive, Product2Id, Product2.Name, Product2.ProductCode, Product2.IsActive';
        if (UserInfo.isMultiCurrencyOrganization()) {
            fields += ', CurrencyIsoCode';
        }
        String name = String.escapeSingleQuotes(cfg.crmPricebookName);
        return 'SELECT ' + fields + ' FROM PricebookEntry'
            + ' WHERE Pricebook2.Name = \'' + name + '\''
            + ' AND IsActive = true AND Product2.IsActive = true AND Product2.ProductCode != null'
            + ' ORDER BY Product2.ProductCode';
    }

    /**
     * @description Moneda del precio: la de la entrada si la org es multimoneda; si no, la configurada.
     * @author Anibal Cortes | 10-26-2026
     * @param pbe Entrada de precio.
     * @return String Código ISO de la moneda (por ejemplo COP).
     **/
    private String resolveCurrency(PricebookEntry pbe) {
        if (UserInfo.isMultiCurrencyOrganization()) {
            Object iso = pbe.get('CurrencyIsoCode');
            if (iso != null) return (String) iso;
        }
        return cfg.currencyCode;
    }

    /**
     * @description Texto de la fila SUMMARY: job, lista, totales, duración y error fatal si lo hubo.
     * @author Anibal Cortes | 10-26-2026
     * @param bc Contexto del batch (para el Id del job).
     * @return String Mensaje del resumen.
     **/
    private String buildSummaryMessage(Database.BatchableContext bc) {
        String msg = 'Job ' + bc.getJobId() + ' | lista "' + (cfg == null ? settingsName : cfg.crmPricebookName) + '"'
            + ' | exitosos: ' + successCount + ' | errores: ' + errorCount;
        if (startedAt != null) {
            msg += ' | duración: ' + (Datetime.now().getTime() - startedAt.getTime()) / 1000 + ' s';
        }
        if (fatalError != null) {
            msg += ' | ERROR FATAL: ' + fatalError;
        }
        return msg;
    }
}
