/**
 * @description Pruebas del job: criterios de aceptación CA1 (carga inicial), CA2 (producto nuevo),
 *              CA3 (re-ejecución sin duplicados y precio actualizado), exclusiones, price book inexistente,
 *              errores por producto sin detener el batch, reintentos y configuración inactiva.
 * @author Anibal Cortes | 10-26-2026
 */
@isTest
private class ICX_PriceSyncBatchTest {

    @TestSetup
    static void setup() {
        ICX_TestDataFactory.createPriceList();
    }

    private static ICX_CommerceApiMock runJob(ICX_CommerceApiMock mock) {
        ICX_TestDataFactory.settings();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Database.executeBatch(new ICX_PriceSyncBatch(), 20);
        Test.stopTest();
        return mock;
    }

    private static Map<String, Commerce_Sync_Log__c> logsByCode() {
        Map<String, Commerce_Sync_Log__c> m = new Map<String, Commerce_Sync_Log__c>();
        for (Commerce_Sync_Log__c l : [SELECT Product_Code__c, Status__c, Operation__c, HTTP_Status__c, Message__c, Unit_Price__c, Currency_Code__c, Success_Count__c, Error_Count__c, Run_Id__c FROM Commerce_Sync_Log__c]) {
            m.put(l.Status__c == 'SUMMARY' ? 'SUMMARY' : l.Product_Code__c, l);
        }
        return m;
    }

    @isTest
    static void ca1CargaInicialCreaProductosYPrecios() {
        ICX_CommerceApiMock mock = runJob(new ICX_CommerceApiMock());
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals(3, logs.size(), 'dos productos + summary: ' + logs.keySet());
        System.assertEquals('SUCCESS', logs.get('ICX-001').Status__c);
        System.assertEquals('producto creado + precio creado', logs.get('ICX-001').Operation__c);
        System.assertEquals(18500, logs.get('ICX-001').Unit_Price__c);
        System.assertEquals('COP', logs.get('ICX-001').Currency_Code__c);
        System.assertEquals('SUCCESS', logs.get('ICX-002').Status__c);
        System.assertEquals(2, logs.get('SUMMARY').Success_Count__c);
        System.assertEquals(0, logs.get('SUMMARY').Error_Count__c);
        System.assert(logs.get('SUMMARY').Message__c.contains('exitosos: 2'));
        // exclusiones: el inactivo y el sin código no viajan
        System.assert(!logs.containsKey('ICX-003'), 'producto inactivo excluido');
        System.assertEquals(2, mock.count('PUT /product/products'), 'dos productos creados');
        System.assertEquals(2, mock.count('PUT /product/price-books'), 'dos precios');
        System.assertEquals(1, mock.count('POST /product/price-books/v1/organizations/f_ecom_test_001/price-book-search'));
        System.assertEquals('Huevos AA x30', mock.existingProducts.get('ICX-001'));
    }

    @isTest
    static void ca3ReejecucionNoDuplicaYActualizaPrecio() {
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        // Commerce ya tiene los dos productos con el mismo nombre (primera corrida ya ocurrió)
        mock.existingProducts.put('ICX-001', 'Huevos AA x30');
        mock.existingProducts.put('ICX-002', 'Salchicha ranchera 500g');
        // cambia un precio en el CRM antes de la segunda corrida
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2.ProductCode = 'ICX-001' AND Pricebook2.Name = :ICX_TestDataFactory.PRICEBOOK_NAME];
        pbe.UnitPrice = 19900; update pbe;
        runJob(mock);
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals(0, mock.count('PUT /product/products'), 'no se crea ningún producto');
        System.assertEquals(0, mock.count('PATCH /product/products'), 'nombres iguales: no hay PATCH');
        System.assertEquals(2, mock.count('PUT /product/price-books'), 'los precios se reescriben siempre');
        System.assertEquals('producto existente + precio creado', logs.get('ICX-001').Operation__c);
        System.assertEquals(19900, logs.get('ICX-001').Unit_Price__c, 'el precio nuevo viaja a Commerce');
        System.assertEquals(2, mock.existingProducts.size(), 'sin duplicados');
    }

    @isTest
    static void ca2ProductoNuevoYNombreCambiado() {
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.existingProducts.put('ICX-001', 'Huevos AA x30 (nombre viejo)');
        // producto agregado "en vivo" a la lista
        Product2 nuevo = new Product2(Name = 'Chorizo santarrosano', ProductCode = 'ICX-004', IsActive = true);
        insert nuevo;
        insert new PricebookEntry(Pricebook2Id = Test.getStandardPricebookId(), Product2Id = nuevo.Id, UnitPrice = 1, IsActive = true);
        Pricebook2 icx = [SELECT Id FROM Pricebook2 WHERE Name = :ICX_TestDataFactory.PRICEBOOK_NAME];
        insert new PricebookEntry(Pricebook2Id = icx.Id, Product2Id = nuevo.Id, UnitPrice = 15700, IsActive = true);
        runJob(mock);
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals('producto creado + precio creado', logs.get('ICX-004').Operation__c, 'el nuevo se crea');
        System.assertEquals('nombre actualizado + precio creado', logs.get('ICX-001').Operation__c, 'el existente solo actualiza nombre');
        System.assertEquals('Huevos AA x30', mock.existingProducts.get('ICX-001'));
        System.assertEquals(1, mock.count('PATCH /product/products'));
        System.assertEquals(3, logs.get('SUMMARY').Success_Count__c);
    }

    @isTest
    static void productoExistenteSinVisibilidadSeHabilitaEnElSitio() {
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.existingProducts.put('ICX-001', 'Huevos AA x30');
        mock.notVisibleForSite.add('ICX-001');
        runJob(mock);
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals('producto existente + visible en RefArch + precio creado', logs.get('ICX-001').Operation__c);
        System.assertEquals(1, mock.count('PATCH /product/products'), 'un PATCH de visibilidad');
        System.assert(!mock.notVisibleForSite.contains('ICX-001'));
    }

    @isTest
    static void errorEnUnProductoNoDetieneAlResto() {
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.failPriceFor.add('ICX-002');
        runJob(mock);
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals('SUCCESS', logs.get('ICX-001').Status__c);
        System.assertEquals('ERROR', logs.get('ICX-002').Status__c);
        System.assertEquals('asignar precio', logs.get('ICX-002').Operation__c);
        System.assertEquals(500, logs.get('ICX-002').HTTP_Status__c);
        System.assert(logs.get('ICX-002').Message__c.contains('3 intento(s)'), 'maxRetries 2 → 3 intentos: ' + logs.get('ICX-002').Message__c);
        System.assertEquals(1, logs.get('SUMMARY').Success_Count__c);
        System.assertEquals(1, logs.get('SUMMARY').Error_Count__c);
        System.assertEquals('Ejecución finalizada', logs.get('SUMMARY').Operation__c);
    }

    @isTest
    static void timeoutEnGetSeRegistraComoExcepcion() {
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.throwOnGet = true;
        runJob(mock);
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals('ERROR', logs.get('ICX-001').Status__c);
        System.assertEquals('excepción', logs.get('ICX-001').Operation__c);
        System.assert(logs.get('ICX-001').Message__c.contains('CommerceApiException'));
        System.assertEquals(2, logs.get('SUMMARY').Error_Count__c);
    }

    @isTest
    static void priceBookInexistenteAbortaConResumen() {
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.priceBookExists = false;
        runJob(mock);
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals(1, logs.size(), 'solo la fila SUMMARY');
        System.assertEquals('Ejecución abortada', logs.get('SUMMARY').Operation__c);
        System.assert(logs.get('SUMMARY').Message__c.contains('no existe en Commerce'), logs.get('SUMMARY').Message__c);
        System.assertEquals(0, mock.count('GET /product/products'), 'no procesa productos');
    }

    @isTest
    static void busquedaDePriceBookConErrorAborta() {
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.failPriceBookSearch = true;
        runJob(mock);
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assertEquals('Ejecución abortada', logs.get('SUMMARY').Operation__c);
        System.assert(logs.get('SUMMARY').Message__c.contains('No se pudo consultar el price book'));
    }

    @isTest
    static void configuracionInactivaAborta() {
        ICX_CommerceSyncSettings s = ICX_TestDataFactory.settings();
        s.active = false;
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        Database.executeBatch(new ICX_PriceSyncBatch('Default'), 20);
        Test.stopTest();
        Map<String, Commerce_Sync_Log__c> logs = logsByCode();
        System.assert(logs.get('SUMMARY').Message__c.contains('inactiva'));
        System.assertEquals(0, mock.requests.size(), 'no hace callouts');
    }

    @isTest
    static void runUsaConfiguracionYDevuelveJobId() {
        ICX_TestDataFactory.settings();
        Test.setMock(HttpCalloutMock.class, new ICX_CommerceApiMock());
        Test.startTest();
        Id jobId = ICX_PriceSyncBatch.run();
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE Id = :jobId].Status);
        System.assertEquals(2, [SELECT COUNT() FROM Commerce_Sync_Log__c WHERE Status__c = 'SUCCESS']);
    }

    @isTest
    static void buildQueryIncluyeFiltros() {
        ICX_TestDataFactory.settings();
        ICX_PriceSyncBatch b = new ICX_PriceSyncBatch();
        // forzar carga de cfg vía start no es posible sin contexto; se valida el SOQL contra los datos
        ICX_CommerceApiMock mock = runJob(new ICX_CommerceApiMock());
        System.assertEquals(2, mock.count('GET /product/products'), 'solo entradas activas con producto activo y con código');
    }
}
