/**
 * @description Datos de prueba comunes: configuración inyectada (sin depender de la Custom Metadata de la org)
 *              y una lista de precios ICX con productos en distintos estados.
 * @author Anibal Cortes | 10-26-2026
 */
@isTest
public class ICX_TestDataFactory {

    public static final String PRICEBOOK_NAME = 'Lista de precios ICX (test)';

    /**
     * @description Configuración de prueba válida e inyectada en ICX_CommerceSyncSettings.testOverride.
     * @author Anibal Cortes | 10-26-2026
     * @return ICX_CommerceSyncSettings Configuración con lote 20 y 2 reintentos.
     **/
    public static ICX_CommerceSyncSettings settings() {
        ICX_CommerceSyncSettings s = new ICX_CommerceSyncSettings();
        s.developerName = 'Default';
        s.organizationId = 'f_ecom_test_001';
        s.siteId = 'RefArch';
        s.catalogId = 'icx-master-catalog';
        s.priceBookId = 'icx-cop-list-prices';
        s.crmPricebookName = PRICEBOOK_NAME;
        s.currencyCode = 'COP';
        s.namedCredential = 'SFCC_Admin_API';
        s.batchSize = 20;
        s.maxRetries = 2;
        s.active = true;
        ICX_CommerceSyncSettings.testOverride = s;
        return s;
    }

    /**
     * @description Crea la lista de precios ICX de prueba con cuatro productos:
     *              ICX-001 y ICX-002 activos con código (se sincronizan), ICX-003 con producto inactivo
     *              (se excluye) y uno activo sin ProductCode (se excluye).
     * @author Anibal Cortes | 10-26-2026
     * @return Pricebook2 La lista de precios creada.
     **/
    public static Pricebook2 createPriceList() {
        Id stdPb = Test.getStandardPricebookId();
        List<Product2> prods = new List<Product2>{
            new Product2(Name = 'Huevos AA x30', ProductCode = 'ICX-001', IsActive = true),
            new Product2(Name = 'Salchicha ranchera 500g', ProductCode = 'ICX-002', IsActive = true),
            new Product2(Name = 'Pollo entero', ProductCode = 'ICX-003', IsActive = false),
            new Product2(Name = 'Sin codigo', IsActive = true)
        };
        insert prods;
        List<PricebookEntry> std = new List<PricebookEntry>();
        for (Product2 p : prods) std.add(new PricebookEntry(Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 1000, IsActive = true));
        insert std;
        Pricebook2 icx = new Pricebook2(Name = PRICEBOOK_NAME, IsActive = true);
        insert icx;
        List<PricebookEntry> entries = new List<PricebookEntry>{
            new PricebookEntry(Pricebook2Id = icx.Id, Product2Id = prods[0].Id, UnitPrice = 18500, IsActive = true),
            new PricebookEntry(Pricebook2Id = icx.Id, Product2Id = prods[1].Id, UnitPrice = 12900, IsActive = true),
            new PricebookEntry(Pricebook2Id = icx.Id, Product2Id = prods[2].Id, UnitPrice = 23400, IsActive = true),
            new PricebookEntry(Pricebook2Id = icx.Id, Product2Id = prods[3].Id, UnitPrice = 999, IsActive = true)
        };
        insert entries;
        return icx;
    }
}
