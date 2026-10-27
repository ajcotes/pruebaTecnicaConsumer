/**
 * @description Simulador de las Admin APIs de B2C Commerce para las pruebas. Enruta cada petición por
 *              método y URL y responde como lo haría SCAPI: 404 RFC 7807 para productos inexistentes,
 *              201/200 en los PUT, resultados de búsqueda de price books, y fallos configurables
 *              (500 permanente para un producto, 503 transitorios, CalloutException). Registra todas las
 *              peticiones para que las pruebas verifiquen qué llamadas se hicieron.
 * @author Anibal Cortes | 10-26-2026
 */
@isTest
public class ICX_CommerceApiMock implements HttpCalloutMock {

    /** Productos que "existen" en Commerce: id → nombre actual. */
    public Map<String, String> existingProducts = new Map<String, String>();
    /** Si el price book configurado existe (afecta a price-book-search). */
    public Boolean priceBookExists = true;
    /** Productos cuyo PUT de precio responde siempre 500. */
    public Set<String> failPriceFor = new Set<String>();
    /** Número de respuestas 503 transitorias antes de responder bien al PUT de precio. */
    public Integer transientPriceFailures = 0;
    /** Si es true, cada GET de producto lanza CalloutException (timeout). */
    public Boolean throwOnGet = false;
    /** Si es true, la búsqueda de price book responde 500. */
    public Boolean failPriceBookSearch = false;

    /** Peticiones recibidas, en orden, como "METHOD path". */
    public List<String> requests = new List<String>();

    /**
     * @description Responde a la petición según método y ruta, imitando el comportamiento de SCAPI.
     * @author Anibal Cortes | 10-26-2026
     * @param req Petición enviada por el cliente.
     * @return HttpResponse Respuesta simulada.
     **/
    public HttpResponse respond(HttpRequest req) {
        String method = req.getMethod();
        String url = req.getEndpoint();
        String path = url.substringAfter('callout:').substringAfter('/');
        requests.add(method + ' /' + path);
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('x-correlation-id', 'mock-' + requests.size());

        if (path.endsWith('/price-book-search') && method == 'POST') {
            if (failPriceBookSearch) return status(res, 500, problem('Internal Server Error', 'simulado'));
            Integer total = priceBookExists ? 1 : 0;
            return status(res, 200, '{"limit":1,"offset":0,"total":' + total + ',"hits":' + (priceBookExists ? '[{"id":"icx-cop-list-prices","currencyCode":"COP","online":true}]' : '[]') + '}');
        }
        if (path.contains('/price-book-entries/') && method == 'PUT') {
            String pid = decode(path.substringAfterLast('/price-book-entries/'));
            if (failPriceFor.contains(pid)) return status(res, 500, problem('Internal Server Error', 'fallo simulado al guardar el precio de ' + pid));
            if (transientPriceFailures > 0) { transientPriceFailures--; return status(res, 503, problem('Service Unavailable', 'transitorio')); }
            Boolean created = !existingPrices.contains(pid);
            existingPrices.add(pid);
            return status(res, created ? 201 : 200, '{"productId":"' + pid + '"}');
        }
        if (path.contains('/products/')) {
            String pid = decode(path.substringAfterLast('/products/'));
            if (method == 'GET') {
                if (throwOnGet) throw new System.CalloutException('Read timed out (simulado)');
                if (!existingProducts.containsKey(pid)) return status(res, 404, problem('Product Not Found', 'No product with ID \'' + pid + '\' could be found.'));
                return status(res, 200, '{"id":"' + pid + '","name":{"default":"' + existingProducts.get(pid) + '"},"online":true}');
            }
            if (method == 'PUT') {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
                existingProducts.put(pid, (String) ((Map<String, Object>) body.get('name')).get('default'));
                return status(res, 201, '{"id":"' + pid + '"}');
            }
            if (method == 'PATCH') {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
                existingProducts.put(pid, (String) ((Map<String, Object>) body.get('name')).get('default'));
                return status(res, 200, '{"id":"' + pid + '"}');
            }
        }
        return status(res, 404, problem('Not Found', 'ruta no simulada: ' + method + ' ' + path));
    }

    private Set<String> existingPrices = new Set<String>();

    /**
     * @description Cuenta cuántas peticiones recibidas empiezan por el prefijo dado, por ejemplo "PUT /product/products".
     * @author Anibal Cortes | 10-26-2026
     * @param prefix Prefijo "METHOD /ruta".
     * @return Integer Número de peticiones que coinciden.
     **/
    public Integer count(String prefix) {
        Integer n = 0;
        for (String r : requests) if (r.startsWith(prefix)) n++;
        return n;
    }

    private static HttpResponse status(HttpResponse res, Integer code, String body) {
        res.setStatusCode(code);
        res.setBody(body);
        return res;
    }

    private static String problem(String title, String detail) {
        return '{"title":"' + title + '","type":"https://api.commercecloud.salesforce.com/documentation/error/v1/errors/x","detail":"' + detail + '"}';
    }

    private static String decode(String v) {
        return EncodingUtil.urlDecode(v, 'UTF-8');
    }
}
