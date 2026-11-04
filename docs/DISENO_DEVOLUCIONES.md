# Diseño — Devoluciones y reingreso al almacén (addendum v3.3)

**Estado:** implementado, con la detección **apagada por defecto** hasta verificar los datos en la base real · **Actualizado:** 4-nov-2026 · **Solicitado por:** Carlos Omar
**Solicitud a la API:** [SOLICITUD_API_DEVOLUCIONES.md](SOLICITUD_API_DEVOLUCIONES.md)

> RM/POSDPS sigue siendo **solo lectura**. La app lee por RMApiV2 y escribe solo en sus archivos (`data.json`, `ledger.json`, `settings.json`) en el servidor central.

## 1. Objetivo

Las devoluciones (`V…`, Transaccion 70) y las anulaciones parciales (`VP…`, 71) del **almacén central** se registran como **devolución**, no como recibo. Pasan por una revisión en **Auditoría ▸ Devoluciones** y, al aceptarlas, van a «Recibido sin ubicar» para ubicarlas en canastas con el flujo de siempre.

## 2. Decisiones del cliente

| # | Tema | Decisión |
|---|---|---|
| 1 | Alcance | Solo el almacén central. |
| 2 | Revisión | Obligatoria, en la pestaña nueva **Devoluciones** de Auditoría. |
| 3 | «No estaba aquí» del piqueo | También sale en esa pestaña (misma fuente que Pendientes; ambas vistas siguen). |
| 4 | Fecha de entrada (FIFO) | La de la venta original si se conoce; si no, la de la devolución. Editable; no puede ser futura. |
| 5 | Orden cancelada en RM | Se quita (sin cambios). Si ya se empezó a piquear, queda «Cerrada en RM (revisar)». |
| 6 | Endpoint nuevo | `SalesReturnsByDate`, pedido a la API. Mientras no exista, la app usa `SalesInvoicesByDate`. |
| 7 | Quién revisa | Permiso propio **«Auditoría: revisar devoluciones»** (Administrador y Supervisor lo traen). |
| 8 | Primera detección | 30 días hacia atrás (editable, máx. 31). |
| 9 | Mercancía que el almacén no despachó | Se importa, pero con aviso. Ver §4. |
| 10 | Llegan menos unidades | Al aceptar, la diferencia queda **descartada** («No llegó al almacén»). |

## 3. Detección (sincronización)

- Paso **Devoluciones**, después de Facturas y solo para el almacén central. Corre solo si está activado en **Administración ▸ Parámetros ▸ Sincronización con RM** («Detectar devoluciones»).
- La ventana es independiente del resto de la sincronización. La primera vez cubre `returnsFirstRunDays` (30) hacia atrás. Después va desde la última detección correcta menos 1 día. Si falla, la fecha no avanza.
- Fuente: `SalesReturnsByDate`. Si la API responde que no existe, se usan las líneas 70/71 de `SalesInvoicesByDate`:
  - la cantidad se toma en **valor absoluto**; si viene en 0, se usa `VoidedQuantity`;
  - el `VoidParcial` de la factura original **nunca** se usa, para no contar dos veces.
- Se omiten servicios, combustible, datos incompletos y cantidades que redondean a 0. Las fraccionarias se redondean y se cuentan.
- Sin duplicados: clave `tienda|documento|LineID`. Además, si cambia el LineID, una línea con el mismo documento, artículo y cantidad que una ya registrada se reconoce.

## 4. ¿Salió la mercancía del almacén?

Una devolución de una venta en caja, o una anulación de una factura que se ajustó antes de piquearse, crearía inventario que no existe. Para evitarlo, cada devolución se cruza con el libro de despachos (`ledger.json`) usando la factura original:

| Aviso | Significado | Acción por defecto |
|---|---|---|
| Despachada por almacén | El almacén piqueó ese artículo para la factura | Aceptar |
| Despachadas N de M | Se piqueó menos de lo devuelto | Aceptar (revisar la cantidad) |
| No salió del almacén | La factura entró, pero no se piqueó ese artículo | **Descartar** |
| Origen desconocido | Venta en caja, otra fecha, más de 90 días o sin factura original | El revisor decide |

«Aceptar seleccionadas» omite las que no salieron del almacén; esas se revisan una por una.

## 5. Revisión (Auditoría ▸ Devoluciones)

Una bandeja con dos tipos de elemento: **Devolución** (RM) y **No encontrado** (piqueo). Tiene filtros por tipo, fecha y texto (producto, documento, cliente), y vistas «Por revisar» y «Revisados».

| Acción | Efecto |
|---|---|
| **Aceptar** | Pide cantidad, fecha de entrada, condición y nota. Crea el recibo `DEV-n` (tipo devolución, factura original como referencia) en «Recibido sin ubicar». |
| **Dar de baja** | Llegó dañada o defectuosa: no entra al inventario. Queda un movimiento `baja`. Si es parte, el resto sigue por revisar. |
| **Descartar** | No llegó o nunca salió: no mueve inventario. Si es parte, el resto sigue por revisar. |
| Encontrado / Dar de baja (no encontrado) | Igual que en Pendientes. Vuelve con su lote y fecha originales. |

Toda acción queda en `audit.log`.

Al **ubicar** un recibo de devolución:
- se crea una fila de inventario **propia**, con la fecha elegida y un lote nuevo, sin mezclarse con otra fila del mismo producto en esa canasta;
- se registra el movimiento **Devolución**;
- las canastas en auditoría se respetan.

## 6. Datos

- `data.json`:
  - `returns` (`ReturnEntry`, ids `DEV-n`), `importedReturnIds` y `seq.return` (inicia en 1001).
  - `Receipt.kind` (`devolucion`) y `Receipt.refDoc`.
  - Un archivo anterior carga sin migración.
- `settings.json`: `returnsEnabled` (falso), `returnsFirstRunDays` (30) y `returnsLastSync`.
- `users.json`:
  - nueva área `returns` y `permsVersion` 3;
  - un archivo v1 o v2 recibe el área del preset del rol (Administrador y Supervisor sí; los demás no).
- Acciones remotas:
  - `acceptReturn`, `acceptReturns`, `writeOffReturn` y `discardReturn` piden «revisar devoluciones»;
  - `resolvePickMissingFound` y `writeOffPickMissing` piden ese permiso o el de administrar auditorías, y solo actúan sobre faltantes del piqueo.

## 7. Para activarlo

1. Correr las consultas de verificación (abajo) en la base del almacén central y confirmar:
   - el signo de las cantidades en V/VP;
   - que una VP no se cuenta dos veces;
   - que `LineID` viene en las líneas 70/71.
2. Entregar la solicitud a la API.
3. Activar «Detectar devoluciones» en Parámetros. La primera corrida trae 30 días.
4. Piloto: comparar la bandeja contra los reportes de devoluciones de RM.
5. Cuando exista `SalesReturnsByDate`, la app lo usa sola (no requiere cambios).

## 8. Verificación en la base real (solo lectura)

```sql
-- 1) Tipos de transacción (vivas + histórico)
SELECT Transaccion, COUNT(*) n FROM (
  SELECT Transaccion FROM Facturas UNION ALL SELECT Transaccion FROM FacturasHisto) x
GROUP BY Transaccion ORDER BY Transaccion;

-- 2) Signo de cantidades en documentos V / VP
SELECT TOP 30 f.Factura, f.Fecha, f.Transaccion, d.Referencia, d.CantidadDespachada, d.VoidParcial
FROM Facturas f JOIN FacturasDetalle d ON d.FacturaNumero = f.Factura
WHERE f.Transaccion IN (70, 71) ORDER BY f.Fecha DESC;

-- 3) ¿VoidDetalle detalla los V/VP?
SELECT TOP 30 f.Factura, f.Transaccion, v.VoidNumber, v.Referencia, v.Cantidad
FROM Facturas f JOIN VoidDetalle v ON v.VoidNumber = f.Factura
WHERE f.Transaccion IN (70, 71) ORDER BY f.Fecha DESC;

-- 4) Posible doble conteo
SELECT TOP 30 d.FacturaNumero, d.Referencia, d.CantidadDespachada, d.VoidParcial
FROM FacturasDetalle d WHERE d.VoidParcial > 0 ORDER BY d.Id DESC;

-- 5) ¿Una devolución descuenta Vendido?
SELECT Referencia, BalanceInicial, Recibido, Vendido, BalanceInicial + Recibido - Vendido AS Existencia
FROM Inventario WHERE Referencia = '<código>';
```

## 9. Pruebas

Las pruebas automáticas están en `test/returns_test.dart`, más casos nuevos en `test/audit_widgets_test.dart` y `server/test/server_test.dart`. Cubren:
- fuente provisional;
- duplicados, incluido el cambio de LineID;
- exclusiones;
- fecha de entrada;
- aviso de despacho;
- aceptar, aceptar en parte, dar de baja y descartar;
- ubicación con fila propia;
- bloqueo por auditoría;
- migración de permisos;
- compatibilidad de `data.json`;
- ventana de sincronización;
- permisos en el servidor;
- pantallas sin desbordes a 360 y 1440 px.
