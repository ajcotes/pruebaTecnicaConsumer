/**
 * @description Pruebas de la programación del job.
 * @author Anibal Cortes | 10-26-2026
 */
@isTest
private class ICX_PriceSyncSchedulerTest {

    @isTest
    static void scheduleCreaCronTriggerYEjecuta() {
        ICX_TestDataFactory.settings();
        Test.setMock(HttpCalloutMock.class, new ICX_CommerceApiMock());
        Test.startTest();
        Id cronId = ICX_PriceSyncScheduler.scheduleDaily(2);
        Id cronId2 = ICX_PriceSyncScheduler.schedule('ICX test cron', '0 0 * * * ?');
        Test.stopTest();
        CronTrigger ct = [SELECT Id, CronExpression, CronJobDetail.Name FROM CronTrigger WHERE Id = :cronId];
        System.assertEquals('0 0 2 * * ?', ct.CronExpression);
        System.assertEquals(ICX_PriceSyncScheduler.DEFAULT_JOB_NAME, ct.CronJobDetail.Name);
        System.assertNotEquals(null, cronId2);
        // execute() del Schedulable encola el batch sin error
        new ICX_PriceSyncScheduler().execute(null);
    }
}
