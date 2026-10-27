/**
 * @description Cliente HTTP para las Admin APIs de B2C Commerce (SCAPI): Products y Price Books.
 *              Es el único punto de la integración que hace callouts. Usa la Named Credential
 *              SFCC_Admin_API, que resuelve la URL base y agrega el token OAuth obtenido con la External
 *              Credential SFCC_Account_Manager; por eso no hay credenciales ni endpoints en código.
 *              Cada operación arma el JSON y delega en send(), que concentra reintentos, cabeceras y errores.
 * @author Anibal Cortes | 10-26-2026
 */
public with sharing class ICX_CommerceApiClient {

    /**
     * @description Excepción propia para fallos de comunicación que agotaron los reintentos
     *              (timeouts o errores de red) y para errores fatales de verificación.
     */
    public class CommerceApiException extends Exception {}

    /**
     * @description Resultado de un callout con lo necesario para decidir el siguiente paso y para el log:
     *              código HTTP, cuerpo, correlation-id, método, ruta e intentos realizados.
     */
    public class ApiResponse {
        public Integer statusCode;
        public String body;
        public String correlationId;
        public String method;
        public String path;
        public Integer attempts = 1;

        /**
         * @description Indica si la respuesta fue exitosa (2xx).
         * @return Boolean true para códigos 200 a 299.
         **/
        public Boolean isSuccess() {
            return statusCode != null && statusCode >= 200 && statusCode < 300;
        }

        /**
         * @description Indica si el recurso no existe (404). Es la señal que usa el job para crear el producto.
         * @return Boolean true si el código es 404.
         **/
        public Boolean isNotFound() {
            return statusCode == 404;
        }

        /**
         * @description Extrae un mensaje legible del error. SCAPI responde en formato RFC 7807
         *              ({title, detail}); si el cuerpo no es JSON devuelve el cuerpo abreviado.
         * @return String Texto para registrar en el log.
         **/
        public String errorDetail() {
            if (String.isBlank(body)) return 'HTTP ' + statusCode + ' sin cuerpo';
            try {
                Map<String, Object> m = bodyAsMap();
                String title = (String) m.get('title');
                String detail = (String) m.get('detail');
                String txt = String.isBlank(title) ? '' : title;
                if (String.isNotBlank(detail)) txt += (txt == '' ? '' : ': ') + detail;
                return String.isBlank(txt) ? body.abbreviate(255) : txt;
            } catch (Exception e) {
                return body.abbreviate(255);
            }
        }

        /**
         * @description Deserializa el cuerpo JSON como mapa. Si el cuerpo está vacío o no es un objeto,
         *              devuelve un mapa vacío en lugar de fallar.
         * @return Map<String, Object> Cuerpo de la respuesta como mapa.
         **/
        public Map<String, Object> bodyAsMap() {
            if (String.isBlank(body)) return new Map<String, Object>();
            Object o = JSON.deserializeUntyped(body);
            return o instanceof Map<String, Object> ? (Map<String, Object>) o : new Map<String, Object>();
        }
    }

    private final ICX_CommerceSyncSettings cfg;
    @TestVisible private Integer timeoutMs = 60000;

    /**
     * @description Construye el cliente con la configuración que define rutas, catálogo, sitio y price book.
     * @author Anibal Cortes | 10-26-2026
     * @param cfg Configuración cargada desde la Custom Metadata.
     **/
    public ICX_CommerceApiClient(ICX_CommerceSyncSettings cfg) {
        this.cfg = cfg;
    }

    // ---------------- Products API

    /**
     * @description Consulta un producto por su ID (el ProductCode del CRM). 200 si existe, 404 si no.
     * @author Anibal Cortes | 10-26-2026
     * @param productId ID del producto en Commerce.
     * @return ApiResponse Respuesta del GET /products/{productId}.
     **/
    public ApiResponse getProduct(String productId) {
        return send('GET', cfg.productsPath() + '/' + enc(productId), null);
    }

    /**
     * @description Crea el producto en el catálogo maestro configurado con su nombre por defecto. Si hay
     *              sitio configurado lo marca online y buscable para ese sitio (onlineFlag y searchable son
     *              mapas por sitio en SCAPI). Usa PUT /products/{productId}, que crea o sobrescribe; por eso
     *              el job solo lo llama cuando el GET devolvió 404.
     * @author Anibal Cortes | 10-26-2026
     * @param productId ID del producto (ProductCode del CRM).
     * @param name Nombre del producto (Product2.Name).
     * @return ApiResponse 201 si lo creó.
     **/
    public ApiResponse createProduct(String productId, String name) {
        Map<String, Object> body = new Map<String, Object>{
            'id' => productId,
            'owningCatalogId' => cfg.catalogId,
            'name' => new Map<String, Object>{ 'default' => name }
        };
        if (cfg.hasSite()) {
            body.put('onlineFlag', new Map<String, Object>{ cfg.siteId => true });
            body.put('searchable', new Map<String, Object>{ cfg.siteId => true });
        }
        return send('PUT', cfg.productsPath() + '/' + enc(productId), JSON.serialize(body));
    }

    /**
     * @description Actualiza solo el nombre de un producto existente con PATCH, sin tocar el resto del
     *              documento (categorías, imágenes, atributos). El job lo usa cuando el nombre del CRM cambió.
     * @author Anibal Cortes | 10-26-2026
     * @param productId ID del producto en Commerce.
     * @param name Nuevo nombre.
     * @return ApiResponse 200 si lo actualizó.
     **/
    public ApiResponse updateProductName(String productId, String name) {
        Map<String, Object> body = new Map<String, Object>{
            'name' => new Map<String, Object>{ 'default' => name }
        };
        return send('PATCH', cfg.productsPath() + '/' + enc(productId), JSON.serialize(body));
    }

    /**
     * @description Marca un producto existente como online y buscable para el sitio configurado (PATCH de
     *              onlineFlag y searchable). Se usa cuando el producto ya existía en Commerce pero no tenía
     *              los flags del sitio, por ejemplo tras cambiar el sitio de destino en la configuración.
     * @author Anibal Cortes | 10-26-2026
     * @param productId ID del producto en Commerce.
     * @return ApiResponse 200 si lo actualizó.
     **/
    public ApiResponse ensureSiteVisibility(String productId) {
        Map<String, Object> body = new Map<String, Object>{
            'onlineFlag' => new Map<String, Object>{ cfg.siteId => true },
            'searchable' => new Map<String, Object>{ cfg.siteId => true }
        };
        return send('PATCH', cfg.productsPath() + '/' + enc(productId), JSON.serialize(body));
    }

    /**
     * @description Indica si el documento de producto devuelto por getProduct ya está online y buscable para
     *              el sitio configurado. SCAPI devuelve los mapas por sitio con claves "default@{siteId}".
     * @author Anibal Cortes | 10-26-2026
     * @param res Respuesta del GET de producto.
     * @param siteId ID del sitio.
     * @return Boolean true si ambos flags están en true para el sitio; false si falta alguno o no hay sitio.
     **/
    public static Boolean isVisibleForSite(ApiResponse res, String siteId) {
        if (String.isBlank(siteId)) return true;
        try {
            Map<String, Object> m = res.bodyAsMap();
            return flagForSite(m.get('onlineFlag'), siteId) && flagForSite(m.get('searchable'), siteId);
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean flagForSite(Object flags, String siteId) {
        if (!(flags instanceof Map<String, Object>)) return false;
        Map<String, Object> f = (Map<String, Object>) flags;
        Object v = f.containsKey('default@' + siteId) ? f.get('default@' + siteId) : f.get(siteId);
        return v == true;
    }

    /**
     * @description Lee name.default del documento de producto devuelto por getProduct.
     * @author Anibal Cortes | 10-26-2026
     * @param res Respuesta del GET de producto.
     * @return String Nombre por defecto, o null si no viene o el cuerpo no se puede leer.
     **/
    public static String productNameFrom(ApiResponse res) {
        try {
            Object n = res.bodyAsMap().get('name');
            if (n instanceof Map<String, Object>) {
                return (String) ((Map<String, Object>) n).get('default');
            }
        } catch (Exception e) {
            // sin nombre
        }
        return null;
    }

    // ---------------- Price Books API

    /**
     * @description Verifica que el price book configurado exista usando POST /price-book-search con un
     *              termQuery por id. Se usa la búsqueda y no GET /price-books/{id} porque en el sandbox
     *              blsb-001 ese endpoint responde "Site Not Found" aunque el price book exista.
     * @author Anibal Cortes | 10-26-2026
     * @return ApiResponse 200 con {total, hits}; total 0 significa que no existe.
     **/
    public ApiResponse findPriceBook() {
        Map<String, Object> body = new Map<String, Object>{
            'query' => new Map<String, Object>{
                'termQuery' => new Map<String, Object>{
                    'fields' => new List<String>{ 'id' },
                    'operator' => 'is',
                    'values' => new List<String>{ cfg.priceBookId }
                }
            },
            'limit' => 1
        };
        return send('POST', cfg.priceBooksBase() + '/price-book-search', JSON.serialize(body));
    }

    /**
     * @description Interpreta la respuesta de findPriceBook.
     * @author Anibal Cortes | 10-26-2026
     * @param res Respuesta de la búsqueda.
     * @return Boolean true si fue exitosa y total es mayor que cero.
     **/
    public static Boolean priceBookFound(ApiResponse res) {
        if (res == null || !res.isSuccess()) return false;
        Object total = res.bodyAsMap().get('total');
        return total != null && Integer.valueOf(total) > 0;
    }

    /**
     * @description Crea o reemplaza el precio del producto en el price book configurado con un único
     *              tramo de cantidad 1 (PUT /price-books/{priceBookId}/price-book-entries/{productId}).
     *              Es idempotente: ejecutarlo varias veces deja el mismo precio, sin duplicados.
     * @author Anibal Cortes | 10-26-2026
     * @param productId ID del producto en Commerce.
     * @param price Precio unitario (PricebookEntry.UnitPrice).
     * @param currencyCode Moneda ISO del precio, debe coincidir con la del price book.
     * @return ApiResponse 201 si creó la entrada, 200 si la reemplazó.
     **/
    public ApiResponse upsertPrice(String productId, Decimal price, String currencyCode) {
        Map<String, Object> tier = new Map<String, Object>{
            'type' => 'amount',
            'quantity' => 1,
            'amount' => new Map<String, Object>{ 'currencyMnemonic' => currencyCode, 'value' => price }
        };
        Map<String, Object> body = new Map<String, Object>{
            'productId' => productId,
            'priceTables' => new List<Object>{ new Map<String, Object>{ 'tiers' => new List<Object>{ tier } } }
        };
        return send('PUT', cfg.priceBooksBase() + '/price-books/' + enc(cfg.priceBookId) + '/price-book-entries/' + enc(productId), JSON.serialize(body));
    }

    // ---------------- HTTP

    /**
     * @description Envía la petición a Commerce a través de la Named Credential. Agrega Accept, un
     *              correlation-id propio (Commerce lo devuelve como x-correlation-id para rastrear la
     *              llamada en Log Center) y Content-Type cuando hay cuerpo. Reintenta hasta cfg.maxRetries
     *              veces ante 429, 5xx o CalloutException (timeout/red); no reintenta 4xx porque son
     *              errores de datos o de permisos que no cambian al repetir.
     * @author Anibal Cortes | 10-26-2026
     * @param method Verbo HTTP (GET, PUT, PATCH, POST).
     * @param path Ruta relativa a la Named Credential.
     * @param body Cuerpo JSON o null.
     * @return ApiResponse Última respuesta recibida (puede ser un 429/5xx si se agotaron los reintentos).
     * @throws CommerceApiException Si todos los intentos terminaron en CalloutException.
     **/
    @TestVisible
    private ApiResponse send(String method, String path, String body) {
        ApiResponse res = new ApiResponse();
        res.method = method;
        res.path = path;
        String correlationId = 'icx-' + String.valueOf(Math.abs(Crypto.getRandomInteger())) + '-' + String.valueOf(Datetime.now().getTime());
        Integer maxAttempts = (cfg.maxRetries == null ? 0 : cfg.maxRetries) + 1;
        Exception last;
        for (Integer attempt = 1; attempt <= maxAttempts; attempt++) {
            res.attempts = attempt;
            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(cfg.calloutBase() + path);
                req.setMethod(method);
                req.setTimeout(timeoutMs);
                req.setHeader('Accept', 'application/json');
                req.setHeader('correlation-id', correlationId);
                if (body != null) {
                    req.setHeader('Content-Type', 'application/json');
                    req.setBody(body);
                }
                HttpResponse http = new Http().send(req);
                res.statusCode = http.getStatusCode();
                res.body = http.getBody();
                String cid = http.getHeader('x-correlation-id');
                res.correlationId = String.isBlank(cid) ? correlationId : cid;
                last = null;
                if (res.statusCode == 429 || res.statusCode >= 500) {
                    continue; // transitorio: reintentar
                }
                return res;
            } catch (System.CalloutException e) {
                last = e;
                res.statusCode = 0;
                res.body = e.getMessage();
                res.correlationId = correlationId;
            }
        }
        if (last != null) {
            throw new CommerceApiException('Callout ' + method + ' ' + path + ' falló tras ' + maxAttempts + ' intento(s): ' + last.getMessage());
        }
        return res; // último 429/5xx
    }

    /**
     * @description Codifica un segmento de URL (IDs de producto o price book pueden traer espacios o símbolos).
     * @author Anibal Cortes | 10-26-2026
     * @param v Valor a codificar.
     * @return String Valor seguro para usar en la ruta.
     **/
    private static String enc(String v) {
        return EncodingUtil.urlEncode(v, 'UTF-8').replace('+', '%20');
    }
}
