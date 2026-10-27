/**
 * @description Configuración (no secreta) de la integración CRM → B2C Commerce, leída del
 *              Custom Metadata Type Commerce_Sync_Setting__mdt. Centraliza los identificadores de
 *              Commerce (organización, sitio, catálogo maestro, price book), el nombre de la lista de
 *              precios del CRM, la moneda, la Named Credential y los parámetros del job (lote, reintentos).
 *              Los secretos (client id / secret de Account Manager) nunca pasan por aquí: viven en la
 *              External Credential SFCC_Account_Manager.
 * @author Anibal Cortes | 10-26-2026
 */
public with sharing class ICX_CommerceSyncSettings {

    /**
     * @description Excepción propia para errores de configuración (registro inexistente o incompleto).
     */
    public class SettingsException extends Exception {}

    /** Developer name del registro de Custom Metadata que usa el job por defecto. */
    public static final String DEFAULT_RECORD = 'Default';

    /** Permite a las clases de prueba inyectar una configuración sin depender de la org. */
    @TestVisible private static ICX_CommerceSyncSettings testOverride;

    public String developerName;
    public String organizationId;
    public String siteId;
    public String catalogId;
    public String priceBookId;
    public String crmPricebookName;
    public String currencyCode;
    public String namedCredential;
    public Integer batchSize = 20;
    public Integer maxRetries = 2;
    public Boolean active = true;

    /**
     * @description Carga el registro de Commerce_Sync_Setting__mdt indicado y lo convierte en un objeto
     *              de configuración ya validado. Si la moneda viene vacía usa la de la org; si el lote o
     *              los reintentos vienen vacíos aplica 20 y 2. En contexto de prueba, si se definió
     *              testOverride, lo devuelve sin consultar la Custom Metadata.
     * @author Anibal Cortes | 10-26-2026
     * @param devName Developer name del registro de Custom Metadata (normalmente "Default").
     * @return ICX_CommerceSyncSettings Configuración lista para usar por el job y el cliente de API.
     * @throws SettingsException Si el registro no existe o le falta algún valor obligatorio.
     **/
    public static ICX_CommerceSyncSettings load(String devName) {
        if (Test.isRunningTest() && testOverride != null) {
            return testOverride;
        }
        Commerce_Sync_Setting__mdt m = Commerce_Sync_Setting__mdt.getInstance(devName);
        if (m == null) {
            throw new SettingsException('No existe el registro Commerce_Sync_Setting__mdt "' + devName + '".');
        }
        ICX_CommerceSyncSettings s = new ICX_CommerceSyncSettings();
        s.developerName = devName;
        s.organizationId = m.Organization_Id__c;
        s.siteId = m.Site_Id__c;
        s.catalogId = m.Catalog_Id__c;
        s.priceBookId = m.Price_Book_Id__c;
        s.crmPricebookName = m.CRM_Pricebook_Name__c;
        s.currencyCode = String.isBlank(m.Currency_Code__c) ? UserInfo.getDefaultCurrency() : m.Currency_Code__c;
        s.namedCredential = m.Named_Credential__c;
        s.batchSize = m.Batch_Size__c == null ? 20 : Integer.valueOf(m.Batch_Size__c);
        s.maxRetries = m.Max_Retries__c == null ? 2 : Integer.valueOf(m.Max_Retries__c);
        s.active = m.Active__c == true;
        s.validate();
        return s;
    }

    /**
     * @description Comprueba que estén los cinco valores obligatorios (organización, catálogo, price book,
     *              nombre de la lista del CRM y Named Credential) y normaliza los opcionales: el lote se
     *              fuerza entre 1 y 30 porque cada producto consume hasta 3 callouts y el límite de Apex
     *              es 100 por transacción; los reintentos entre 0 y 5; la moneda vacía toma la de la org.
     * @author Anibal Cortes | 10-26-2026
     * @throws SettingsException Si falta algún valor obligatorio; el mensaje lista los campos ausentes.
     **/
    public void validate() {
        List<String> missing = new List<String>();
        if (String.isBlank(organizationId)) missing.add('Organization_Id__c');
        if (String.isBlank(catalogId)) missing.add('Catalog_Id__c');
        if (String.isBlank(priceBookId)) missing.add('Price_Book_Id__c');
        if (String.isBlank(crmPricebookName)) missing.add('CRM_Pricebook_Name__c');
        if (String.isBlank(namedCredential)) missing.add('Named_Credential__c');
        if (!missing.isEmpty()) {
            throw new SettingsException('Configuración incompleta en Commerce_Sync_Setting__mdt: ' + String.join(missing, ', '));
        }
        // Cada producto consume hasta 3 callouts y el límite por transacción es 100.
        if (batchSize == null || batchSize < 1 || batchSize > 30) batchSize = 20;
        if (maxRetries == null || maxRetries < 0 || maxRetries > 5) maxRetries = 2;
        if (String.isBlank(currencyCode)) currencyCode = UserInfo.getDefaultCurrency();
    }

    /**
     * @description Indica si hay un sitio de Commerce configurado. Cuando lo hay, el producto se crea
     *              online y buscable para ese sitio; cuando no, se crea sin flags de sitio.
     * @author Anibal Cortes | 10-26-2026
     * @return Boolean true si Site_Id__c tiene valor.
     **/
    public Boolean hasSite() {
        return String.isNotBlank(siteId);
    }

    /**
     * @description Prefijo de endpoint que usa la Named Credential ("callout:SFCC_Admin_API").
     *              Salesforce lo reemplaza por la URL real y agrega el token OAuth en cada callout.
     * @author Anibal Cortes | 10-26-2026
     * @return String Prefijo "callout:" + nombre de la Named Credential.
     **/
    public String calloutBase() {
        return 'callout:' + namedCredential;
    }

    /**
     * @description Ruta base de la Products API de SCAPI para esta organización
     *              (/product/products/v1/organizations/{organizationId}/products).
     * @author Anibal Cortes | 10-26-2026
     * @return String Ruta relativa a la que se concatena "/{productId}".
     **/
    public String productsPath() {
        return '/product/products/v1/organizations/' + organizationId + '/products';
    }

    /**
     * @description Ruta base de la Price Books API de SCAPI para esta organización
     *              (/product/price-books/v1/organizations/{organizationId}). A partir de ella se forman
     *              "/price-book-search" y "/price-books/{priceBookId}/price-book-entries/{productId}".
     * @author Anibal Cortes | 10-26-2026
     * @return String Ruta relativa base de la Price Books API.
     **/
    public String priceBooksBase() {
        return '/product/price-books/v1/organizations/' + organizationId;
    }
}
