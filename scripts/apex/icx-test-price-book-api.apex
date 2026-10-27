Commerce_Sync_Setting__mdt cfg = Commerce_Sync_Setting__mdt.getInstance('Default');
String base = 'callout:' + cfg.Named_Credential__c + '/product/price-books/v1/organizations/' + cfg.Organization_Id__c;
HttpResponse r;
// 1. PUT crear price book
HttpRequest put = new HttpRequest(); put.setEndpoint(base + '/price-books/' + cfg.Price_Book_Id__c); put.setMethod('PUT'); put.setHeader('Content-Type','application/json'); put.setTimeout(60000);
put.setBody(JSON.serialize(new Map<String,Object>{ 'id' => cfg.Price_Book_Id__c, 'displayName' => 'ICX Lista de precios (COP)', 'description' => 'Precios sincronizados desde la Lista de precios ICX del CRM', 'currencyCode' => cfg.Currency_Code__c, 'online' => true }));
r = new Http().send(put); System.debug('ICXTEST PUT price-book -> ' + r.getStatusCode() + ' ' + r.getBody().abbreviate(200));
// 2. GET por id
HttpRequest g = new HttpRequest(); g.setEndpoint(base + '/price-books/' + cfg.Price_Book_Id__c); g.setMethod('GET'); g.setTimeout(60000);
r = new Http().send(g); System.debug('ICXTEST GET price-book -> ' + r.getStatusCode() + ' ' + r.getBody().abbreviate(160));
// 3. search por id
HttpRequest s = new HttpRequest(); s.setEndpoint(base + '/price-book-search'); s.setMethod('POST'); s.setHeader('Content-Type','application/json'); s.setTimeout(60000);
s.setBody('{"query":{"termQuery":{"fields":["id"],"operator":"is","values":["' + cfg.Price_Book_Id__c + '"]}},"limit":1}');
r = new Http().send(s); System.debug('ICXTEST SEARCH price-book -> ' + r.getStatusCode() + ' ' + r.getBody().abbreviate(300));
// 4. PUT asignación al sitio
HttpRequest a = new HttpRequest(); a.setEndpoint(base + '/price-books/' + cfg.Price_Book_Id__c + '/site-assignments/' + cfg.Site_Id__c); a.setMethod('PUT'); a.setHeader('Content-Type','application/json'); a.setTimeout(60000); a.setBody('{"siteId":"' + cfg.Site_Id__c + '"}');
r = new Http().send(a); System.debug('ICXTEST PUT site-assignment -> ' + r.getStatusCode() + ' ' + r.getBody().abbreviate(200));
// 5. GET por id otra vez (ya asignado al sitio)
r = new Http().send(g); System.debug('ICXTEST GET price-book (tras asignar) -> ' + r.getStatusCode() + ' ' + r.getBody().abbreviate(160));
// 6. PUT precio para producto inexistente (esperado 404)
HttpRequest p = new HttpRequest(); p.setEndpoint(base + '/price-books/' + cfg.Price_Book_Id__c + '/price-book-entries/NO-EXISTE-123'); p.setMethod('PUT'); p.setHeader('Content-Type','application/json'); p.setTimeout(60000);
p.setBody('{"productId":"NO-EXISTE-123","priceTables":[{"tiers":[{"type":"amount","quantity":1,"amount":{"currencyMnemonic":"COP","value":1000}}]}]}');
r = new Http().send(p); System.debug('ICXTEST PUT entry producto inexistente -> ' + r.getStatusCode() + ' ' + r.getBody().abbreviate(200));
