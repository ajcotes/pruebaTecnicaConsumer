Pricebook2 icx = [SELECT Id FROM Pricebook2 WHERE Name = 'Lista de precios ICX' LIMIT 1];
Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
Product2 p = new Product2(Name = 'Chorizo santarrosano 400g', ProductCode = 'ICX-EMB-CHO400', IsActive = true, Description = 'Embutido (prueba tecnica ICX, agregado en vivo)');
insert p;
insert new PricebookEntry(Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 15700, IsActive = true);
insert new PricebookEntry(Pricebook2Id = icx.Id, Product2Id = p.Id, UnitPrice = 15700, IsActive = true);
System.debug('ICXCA2 producto nuevo agregado a la lista');
