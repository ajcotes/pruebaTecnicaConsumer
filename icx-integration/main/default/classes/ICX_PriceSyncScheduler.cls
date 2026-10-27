/**
 * @description Ejecución programada del job de sincronización CRM → B2C Commerce. Implementa Schedulable
 *              y delega en ICX_PriceSyncBatch.run(). Ejemplos de uso desde Execute Anonymous:
 *                ICX_PriceSyncScheduler.scheduleDaily(2);                                  // diario a las 02:00
 *                ICX_PriceSyncScheduler.schedule('ICX PriceSync cada hora', '0 0 * * * ?'); // cron propio
 * @author Anibal Cortes | 10-26-2026
 */
public with sharing class ICX_PriceSyncScheduler implements Schedulable {

    /** Nombre con el que queda registrado el job programado en Setup › Scheduled Jobs. */
    public static final String DEFAULT_JOB_NAME = 'ICX PriceSync CRM → Commerce';

    /**
     * @description Método que invoca la plataforma en cada disparo del cron. Lanza el batch con la
     *              configuración "Default" y el tamaño de lote definido en la Custom Metadata.
     * @author Anibal Cortes | 10-26-2026
     * @param sc Contexto del job programado (lo entrega Salesforce).
     **/
    public void execute(SchedulableContext sc) {
        ICX_PriceSyncBatch.run();
    }

    /**
     * @description Programa el job con un nombre y una expresión cron de Salesforce (segundos, minutos,
     *              horas, día del mes, mes, día de la semana, año opcional).
     * @author Anibal Cortes | 10-26-2026
     * @param jobName Nombre visible del job programado.
     * @param cronExpression Expresión cron de Apex, por ejemplo "0 0 2 * * ?".
     * @return Id Id del CronTrigger creado.
     **/
    public static Id schedule(String jobName, String cronExpression) {
        return System.schedule(jobName, cronExpression, new ICX_PriceSyncScheduler());
    }

    /**
     * @description Atajo para programar el job todos los días a una hora fija, en la zona horaria de la org.
     * @author Anibal Cortes | 10-26-2026
     * @param hour Hora del día (0 a 23).
     * @return Id Id del CronTrigger creado.
     **/
    public static Id scheduleDaily(Integer hour) {
        return schedule(DEFAULT_JOB_NAME, '0 0 ' + hour + ' * * ?');
    }
}
