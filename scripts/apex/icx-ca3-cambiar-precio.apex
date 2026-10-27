PricebookEntry pbe = [SELECT Id, UnitPrice FROM PricebookEntry WHERE Pricebook2.Name = 'Lista de precios ICX' AND Product2.ProductCode = 'ICX-HUE-AA30'];
pbe.UnitPrice = 19900; update pbe; System.debug('ICXCA3 precio actualizado en CRM');
