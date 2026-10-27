/**
 * @description Pruebas del cliente de API: cuerpos, rutas, reintentos y manejo de errores.
 * @author Anibal Cortes | 10-26-2026
 */
@isTest
private class ICX_CommerceApiClientTest {

    @isTest
    static void productoCrearConsultarYActualizar() {
        ICX_CommerceSyncSettings cfg = ICX_TestDataFactory.settings();
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        ICX_CommerceApiClient c = new ICX_CommerceApiClient(cfg);
        Test.startTest();
        ICX_CommerceApiClient.ApiResponse r404 = c.getProduct('ICX-001');
        System.assert(r404.isNotFound());
        System.assert(r404.errorDetail().startsWith('Product Not Found'));
        ICX_CommerceApiClient.ApiResponse created = c.createProduct('ICX-001', 'Huevos AA x30');
        System.assertEquals(201, created.statusCode);
        ICX_CommerceApiClient.ApiResponse r200 = c.getProduct('ICX-001');
        System.assert(r200.isSuccess());
        System.assertEquals('Huevos AA x30', ICX_CommerceApiClient.productNameFrom(r200));
        ICX_CommerceApiClient.ApiResponse patched = c.updateProductName('ICX-001', 'Huevos AA x30 nuevo');
        System.assertEquals(200, patched.statusCode);
        Test.stopTest();
        System.assertEquals('Huevos AA x30 nuevo', mock.existingProducts.get('ICX-001'));
        System.assert(mock.requests[1].startsWith('PUT /product/products/v1/organizations/f_ecom_test_001/products/ICX-001'));
    }

    @isTest
    static void cuerpoDeCreacionIncluyeCatalogoYSitio() {
        ICX_CommerceSyncSettings cfg = ICX_TestDataFactory.settings();
        BodyCaptureMock cap = new BodyCaptureMock();
        Test.setMock(HttpCalloutMock.class, cap);
        new ICX_CommerceApiClient(cfg).createProduct('ICX 9', 'Nombre');
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(cap.lastBody);
        System.assertEquals('icx-master-catalog', body.get('owningCatalogId'));
        System.assertEquals(true, ((Map<String, Object>) body.get('onlineFlag')).get('RefArch'));
        System.assertEquals(true, ((Map<String, Object>) body.get('searchable')).get('RefArch'));
        System.assert(cap.lastEndpoint.endsWith('/products/ICX%209'), 'el id debe ir codificado: ' + cap.lastEndpoint);
        cfg.siteId = null;
        new ICX_CommerceApiClient(cfg).createProduct('ICX-9', 'Nombre');
        body = (Map<String, Object>) JSON.deserializeUntyped(cap.lastBody);
        System.assert(!body.containsKey('onlineFlag'), 'sin sitio no se envían flags');
    }

    @isTest
    static void precioYPriceBook() {
        ICX_CommerceSyncSettings cfg = ICX_TestDataFactory.settings();
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        ICX_CommerceApiClient c = new ICX_CommerceApiClient(cfg);
        Test.startTest();
        System.assert(ICX_CommerceApiClient.priceBookFound(c.findPriceBook()));
        mock.priceBookExists = false;
        System.assert(!ICX_CommerceApiClient.priceBookFound(c.findPriceBook()));
        ICX_CommerceApiClient.ApiResponse p1 = c.upsertPrice('ICX-001', 18500, 'COP');
        ICX_CommerceApiClient.ApiResponse p2 = c.upsertPrice('ICX-001', 19000, 'COP');
        Test.stopTest();
        System.assertEquals(201, p1.statusCode, 'primera vez crea');
        System.assertEquals(200, p2.statusCode, 'segunda vez reemplaza');
        System.assert(mock.requests[0].startsWith('POST /product/price-books/v1/organizations/f_ecom_test_001/price-book-search'));
        System.assert(!ICX_CommerceApiClient.priceBookFound(null));
    }

    @isTest
    static void reintentaTransitoriosYNoReintenta4xx() {
        ICX_CommerceSyncSettings cfg = ICX_TestDataFactory.settings();
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.transientPriceFailures = 2; // dos 503 y luego éxito
        Test.setMock(HttpCalloutMock.class, mock);
        ICX_CommerceApiClient c = new ICX_CommerceApiClient(cfg);
        Test.startTest();
        ICX_CommerceApiClient.ApiResponse ok = c.upsertPrice('ICX-001', 100, 'COP');
        ICX_CommerceApiClient.ApiResponse nf = c.getProduct('NO-EXISTE');
        Test.stopTest();
        System.assert(ok.isSuccess(), 'debe terminar bien tras reintentar');
        System.assertEquals(3, ok.attempts);
        System.assertEquals(1, nf.attempts, 'un 404 no se reintenta');
        System.assertEquals(3, mock.count('PUT /product/price-books'));
    }

    @isTest
    static void agotaReintentosCon5xxYLanzaExcepcionConTimeout() {
        ICX_CommerceSyncSettings cfg = ICX_TestDataFactory.settings();
        cfg.maxRetries = 1;
        ICX_CommerceApiMock mock = new ICX_CommerceApiMock();
        mock.failPriceFor.add('ICX-001');
        mock.throwOnGet = true;
        Test.setMock(HttpCalloutMock.class, mock);
        ICX_CommerceApiClient c = new ICX_CommerceApiClient(cfg);
        Test.startTest();
        ICX_CommerceApiClient.ApiResponse r = c.upsertPrice('ICX-001', 100, 'COP');
        System.assertEquals(500, r.statusCode);
        System.assertEquals(2, r.attempts, 'maxRetries 1 → 2 intentos');
        System.assert(r.errorDetail().contains('Internal Server Error'));
        try {
            c.getProduct('ICX-001');
            System.assert(false, 'Debió lanzar CommerceApiException');
        } catch (ICX_CommerceApiClient.CommerceApiException e) {
            System.assert(e.getMessage().contains('2 intento(s)'), e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void apiResponseHelpers() {
        ICX_CommerceApiClient.ApiResponse r = new ICX_CommerceApiClient.ApiResponse();
        r.statusCode = 500; r.body = null;
        System.assertEquals('HTTP 500 sin cuerpo', r.errorDetail());
        r.body = 'texto plano que no es json';
        System.assertEquals('texto plano que no es json', r.errorDetail());
        r.body = '[1,2]';
        System.assertEquals(0, r.bodyAsMap().size());
        r.body = '{"title":"","detail":"solo detalle"}';
        System.assertEquals('solo detalle', r.errorDetail());
        System.assertEquals(null, ICX_CommerceApiClient.productNameFrom(r));
    }

    /** Mock mínimo que captura el último cuerpo y endpoint enviados. */
    private class BodyCaptureMock implements HttpCalloutMock {
        public String lastBody;
        public String lastEndpoint;
        public HttpResponse respond(HttpRequest req) {
            lastBody = req.getBody();
            lastEndpoint = req.getEndpoint();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(201);
            res.setBody('{}');
            return res;
        }
    }
}
