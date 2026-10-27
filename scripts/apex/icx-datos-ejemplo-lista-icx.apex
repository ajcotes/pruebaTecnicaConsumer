Pricebook2 icx = [SELECT Id FROM Pricebook2 WHERE Name = 'Lista de precios ICX' LIMIT 1];
Id stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
List<Product2> prods = new List<Product2>{
    new Product2(Name = 'Huevos AA x30', ProductCode = 'ICX-HUE-AA30', IsActive = true, Description = 'Bandeja de 30 huevos AA (prueba tecnica ICX)'),
    new Product2(Name = 'Huevos AAA x12', ProductCode = 'ICX-HUE-AAA12', IsActive = true, Description = 'Estuche de 12 huevos AAA (prueba tecnica ICX)'),
    new Product2(Name = 'Salchicha ranchera 500g', ProductCode = 'ICX-EMB-SAL500', IsActive = true, Description = 'Embutido (prueba tecnica ICX)')
};
insert prods;
Map<String, Decimal> precios = new Map<String, Decimal>{ 'ICX-HUE-AA30' => 18500, 'ICX-HUE-AAA12' => 9800, 'ICX-EMB-SAL500' => 12900 };
List<PricebookEntry> entries = new List<PricebookEntry>();
for (Product2 p : prods) {
    entries.add(new PricebookEntry(Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = precios.get(p.ProductCode), IsActive = true));
}
insert entries;
entries = new List<PricebookEntry>();
for (Product2 p : prods) {
    entries.add(new PricebookEntry(Pricebook2Id = icx.Id, Product2Id = p.Id, UnitPrice = precios.get(p.ProductCode), IsActive = true));
}
insert entries;
System.debug('ICXSEED creados ' + prods.size() + ' productos y ' + (entries.size() * 2) + ' entradas');
