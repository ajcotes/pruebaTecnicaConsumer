/**
 * @description Pruebas del punto de entrada invocable (Flow / Lightning).
 * @author Anibal Cortes | 10-26-2026
 */
@isTest
private class ICX_PriceSyncInvocableTest {

    @isTest
    static void launchFromFlowDevuelveJobIdYEstado() {
        ICX_TestDataFactory.createPriceList();
        ICX_TestDataFactory.settings();
        Test.setMock(HttpCalloutMock.class, new ICX_CommerceApiMock());
        Test.startTest();
        List<ICX_PriceSyncInvocable.Result> out = ICX_PriceSyncInvocable.launchFromFlow(new List<String>{ 'go' });
        Test.stopTest();
        System.assertEquals(1, out.size());
        System.assertNotEquals(null, out[0].jobId, out[0].message);
        System.assert(out[0].message.startsWith('Job lanzado'));
        Map<String, Object> st = ICX_PriceSyncInvocable.jobStatus(out[0].jobId);
        System.assertEquals('Completed', st.get('status'));
        System.assertEquals(0, st.get('errors'));
    }

    @isTest
    static void launchFromFlowCapturaErrorDeConfiguracion() {
        ICX_CommerceSyncSettings s = ICX_TestDataFactory.settings();
        s.namedCredential = null; // run() valida y falla
        List<ICX_PriceSyncInvocable.Result> out;
        Test.startTest();
        try {
            s.validate();
        } catch (ICX_CommerceSyncSettings.SettingsException e) {
            // esperado: la configuración es inválida
        }
        ICX_CommerceSyncSettings.testOverride = null;
        Test.setMock(HttpCalloutMock.class, new ICX_CommerceApiMock());
        out = ICX_PriceSyncInvocable.launchFromFlow(null);
        Test.stopTest();
        System.assertEquals(1, out.size());
        System.assertNotEquals(null, out[0].message);
    }
}
