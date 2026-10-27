# Configuración del CRM: desbloqueo de despliegues, credenciales y metadata base

Prueba técnica Developer Salesforce · Imagine CX

Registro paso a paso de la Fase B del PRD (`PRD-integracion-ICX.md`) en el sandbox CRM `enterprise-efficiency-9228--mkt` (alias `pruebaTecnicaAnibal`). Cada paso lleva Dónde, Qué se hizo, Resultado y, cuando aplica, su captura en `capturas-configuracion/`.

---

## Fase B · Configurar el CRM

### B.0 Desbloqueo de despliegues: clases obsoletas de la org

**Dónde:** sandbox MKT, clases Apex de Italcol (no son parte de la integración).

**Qué se encontró:** al validar el despliegue de la metadata de la integración, Salesforce rechazó cualquier despliegue a la org, incluso uno trivial de una etiqueta personalizada. La org tenía 42 clases marcadas como inválidas. La causa raíz eran dos clases obsoletas que no compilaban:

| Clase | Error | Origen |
|---|---|---|
| `EnvioPedidoAsync` (9 líneas, ago. 2025) | Llama a `EnvioPedidoService.enviarPedidos(List<Order>)`, método que ya no existe | `EnvioPedidoService` fue reescrita en dic. 2025 y hoy trabaja con pedidos de Consumer Goods Cloud (`cgcloud__Order__c`) |
| `reenviarPedidoController` (13 líneas, ago. 2025) | Llama a `EnvioPedidoService.reintentarPorId(List<Id>)`, método que ya no existe | Misma reescritura |

Las otras 40 clases inválidas solo necesitaban recompilarse: dependían de estas dos. Se descartó que la causa fuera la opción "Compile on Deploy" de la org (está desactivada, verificado en `ApexSettings`).

**Qué se hizo (autorizado por Aníbal):**
1. Se respaldó el cuerpo original de `EnvioPedidoAsync`, `EnvioPedidoAsyncTest`, `reenviarPedidoController` y `reenviarPedidoControllerTest` en la carpeta local `backup-clases-italcol-mkt/`, fuera del repositorio.
2. Se desplegó una versión **desactivada** de `EnvioPedidoAsync` y de `reenviarPedidoController`: se conserva exactamente la misma firma pública (`enviar(Set<Id>)` y `reenviarPedido(Id)` con `@AuraEnabled`) pero sin lógica, con un comentario que explica el motivo y la fecha. Así sus clases de prueba y el componente que invoca al controlador siguen compilando.
3. No se borró ninguna clase ni se tocó `EnvioPedidoService`.

**Resultado:** la org volvió a aceptar despliegues. Una simulación de despliegue (`--dry-run`, sin ejecutar pruebas) de toda la metadata de `icx-integration` se completa sin errores de componente.

**Nota para la sustentación:** `sf project deploy validate` ejecuta por defecto las pruebas de toda la org; las clases de prueba de Italcol tienen 61 % de cobertura y fallos propios, así que en este sandbox el despliegue se hace con `--test-level NoTestRun` y la cobertura de la integración se demuestra ejecutando sus propias clases de prueba.

