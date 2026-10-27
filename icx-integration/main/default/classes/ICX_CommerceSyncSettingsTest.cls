/**
 * @description Pruebas de la carga y validación de la configuración.
 * @author Anibal Cortes | 10-26-2026
 */
@isTest
private class ICX_CommerceSyncSettingsTest {

    @isTest
    static void loadDefaultDesdeCustomMetadata() {
        ICX_CommerceSyncSettings.testOverride = null;
        ICX_CommerceSyncSettings s = ICX_CommerceSyncSettings.load(ICX_CommerceSyncSettings.DEFAULT_RECORD);
        System.assertEquals('Default', s.developerName);
        System.assert(String.isNotBlank(s.organizationId), 'organizationId debe venir de la Custom Metadata');
        System.assert(String.isNotBlank(s.namedCredential));
        System.assert(s.batchSize >= 1 && s.batchSize <= 30);
        System.assert(s.calloutBase().startsWith('callout:'));
        System.assert(s.productsPath().contains(s.organizationId));
        System.assert(s.priceBooksBase().contains(s.organizationId));
    }

    @isTest
    static void loadRegistroInexistenteLanzaExcepcion() {
        ICX_CommerceSyncSettings.testOverride = null;
        try {
            ICX_CommerceSyncSettings.load('No_Existe_XYZ');
            System.assert(false, 'Debió lanzar SettingsException');
        } catch (ICX_CommerceSyncSettings.SettingsException e) {
            System.assert(e.getMessage().contains('No_Existe_XYZ'));
        }
    }

    @isTest
    static void validateDetectaCamposFaltantesYNormaliza() {
        ICX_CommerceSyncSettings s = new ICX_CommerceSyncSettings();
        try {
            s.validate();
            System.assert(false, 'Debió fallar por campos faltantes');
        } catch (ICX_CommerceSyncSettings.SettingsException e) {
            System.assert(e.getMessage().contains('Organization_Id__c'));
            System.assert(e.getMessage().contains('Price_Book_Id__c'));
        }
        s = ICX_TestDataFactory.settings();
        s.batchSize = 500; s.maxRetries = 99; s.currencyCode = null; s.siteId = null;
        s.validate();
        System.assertEquals(20, s.batchSize, 'lote fuera de rango vuelve a 20');
        System.assertEquals(2, s.maxRetries, 'reintentos fuera de rango vuelven a 2');
        System.assertEquals(UserInfo.getDefaultCurrency(), s.currencyCode);
        System.assertEquals(false, s.hasSite());
    }

    @isTest
    static void loadUsaTestOverride() {
        ICX_CommerceSyncSettings s = ICX_TestDataFactory.settings();
        System.assert(ICX_CommerceSyncSettings.load('cualquiera') === s);
    }
}
