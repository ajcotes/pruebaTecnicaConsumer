/**
 * @description Punto de entrada para lanzar el job a demanda. Expone tres formas:
 *              - launchFromFlow (@InvocableMethod): desde un Flow o un botón de acción.
 *              - launch (@AuraEnabled): desde un componente Lightning o Execute Anonymous.
 *              - jobStatus (@AuraEnabled): para consultar el avance del AsyncApexJob.
 * @author Anibal Cortes | 10-26-2026
 */
public with sharing class ICX_PriceSyncInvocable {

    /**
     * @description Resultado que se devuelve al Flow: Id del job lanzado y un mensaje legible.
     */
    public class Result {
        @InvocableVariable(label='Id del job (AsyncApexJob)') public String jobId;
        @InvocableVariable(label='Mensaje') public String message;
    }

    /**
     * @description Acción invocable "Sincronizar Lista ICX con Commerce". Lanza el batch y devuelve el Id
     *              del job; si algo falla al lanzarlo (configuración incompleta, límites), no propaga la
     *              excepción sino que la devuelve en el mensaje para que el Flow la muestre.
     * @author Anibal Cortes | 10-26-2026
     * @param inputs Lista de entradas del Flow; no se usa, pero la firma invocable exige una lista.
     * @return List<Result> Un único resultado con jobId y message.
     **/
    @InvocableMethod(label='Sincronizar Lista ICX con Commerce' description='Lanza el job que lleva productos y precios de la Lista de precios ICX a B2C Commerce.' category='ICX Commerce')
    public static List<Result> launchFromFlow(List<String> inputs) {
        Result r = new Result();
        try {
            r.jobId = launch();
            r.message = 'Job lanzado: ' + r.jobId;
        } catch (Exception e) {
            r.message = 'No se pudo lanzar el job: ' + e.getMessage();
        }
        return new List<Result>{ r };
    }

    /**
     * @description Lanza el batch con la configuración "Default" y devuelve el Id del AsyncApexJob.
     * @author Anibal Cortes | 10-26-2026
     * @return String Id del AsyncApexJob (18 caracteres).
     * @throws Exception Si la configuración es inválida o no se puede encolar el batch.
     **/
    @AuraEnabled
    public static String launch() {
        return ICX_PriceSyncBatch.run();
    }

    /**
     * @description Consulta el estado de un job lanzado: estado, lotes procesados, total y errores.
     * @author Anibal Cortes | 10-26-2026
     * @param jobId Id del AsyncApexJob devuelto por launch.
     * @return Map<String, Object> Claves status, processed, total, errors y completed.
     **/
    @AuraEnabled
    public static Map<String, Object> jobStatus(String jobId) {
        AsyncApexJob j = [SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, CompletedDate
                          FROM AsyncApexJob WHERE Id = :jobId];
        return new Map<String, Object>{
            'status' => j.Status,
            'processed' => j.JobItemsProcessed,
            'total' => j.TotalJobItems,
            'errors' => j.NumberOfErrors,
            'completed' => j.CompletedDate
        };
    }
}
