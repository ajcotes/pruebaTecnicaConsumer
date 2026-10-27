Commerce_Sync_Setting__mdt cfg = Commerce_Sync_Setting__mdt.getInstance('Default');
String base = 'callout:' + cfg.Named_Credential__c;
String org = cfg.Organization_Id__c;
List<String> paths = new List<String>{
    '/product/catalogs/v1/organizations/' + org + '/catalogs/' + cfg.Catalog_Id__c,
    '/product/products/v1/organizations/' + org + '/products/NO-EXISTE-123',
    '/product/price-books/v1/organizations/' + org + '/price-books/' + cfg.Price_Book_Id__c
};
for (String p : paths) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(base + p);
    req.setMethod('GET');
    req.setHeader('Accept', 'application/json');
    req.setTimeout(60000);
    HttpResponse res = new Http().send(req);
    System.debug('ICXTEST ' + res.getStatusCode() + ' GET ' + p + ' -> ' + res.getBody().abbreviate(160));
}
