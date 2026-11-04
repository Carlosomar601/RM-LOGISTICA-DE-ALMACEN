# Solicitud al equipo de la API — Endpoint `SalesReturnsByDate`

**De:** Carlos Omar — Retail Manager PR (proyecto Centeno Tire, módulo de logística de almacén y piqueo)
**Para:** Equipo de RMApiV2
**Fecha:** 4 de noviembre de 2026
**Prioridad:** Media-alta (bloquea la fuente "limpia"; hay una solución provisional)
**Versión de la API actual:** RMApiV2 1.12.0 (`/cse.api.v1/`)

---

## 1. Resumen

Necesitamos un endpoint **solo de lectura** que devuelva, por rango de fechas, las **líneas de mercancía devuelta o anulada** en la base de RM, ya normalizadas: cantidades positivas, sin duplicados entre documentos y con la **factura original y su fecha**. La app de almacén las usa para registrarlas como devoluciones, someterlas a revisión y reingresarlas a bins.

Hoy `SalesInvoicesByDate` entrega líneas de devolución (`Transaction` 70/71) pero la app las ignora porque no es seguro interpretarlas (signo de la cantidad, doble conteo con `VoidParcial`) y falta la fecha de la factura original.

## 2. Contexto

- La app es un cliente de **solo lectura**: no escribe nada en RM.
- Consulta únicamente la base del **almacén central** (para esta fase).
- Sincroniza periódicamente. La **primera corrida pide 30 días**; después, ventanas incrementales (último sync − 1 día). Debe ser seguro pedir el mismo rango varias veces.
- Convenciones actuales que queremos mantener: parámetros `DateFrom` / `DateTo` (`yyyy-MM-dd`, ambos incluidos), máximo **31 días por llamada**, respuesta JSON como lista, campos en PascalCase, comportamiento de errores igual al resto de endpoints.

## 3. Endpoint solicitado

```
GET /cse.api.v1/SalesReturnsByDate?DateFrom=2026-10-05&DateTo=2026-11-03
```

| Parámetro | Obligatorio | Descripción |
|---|---|---|
| `DateFrom` | Sí | Fecha inicial (incluida). Se compara con la fecha del **documento de devolución/anulación**, no con la de la factura original. |
| `DateTo` | Sí | Fecha final (incluida). Máx. 31 días entre ambas. |
| `ReturnNumber` | No | Filtra un documento (`V…`/`VP…`). Útil para pruebas y soporte. |

Orden: por `ReturnDate`, `ReturnTime`, `ReturnNumber`, `LineID` ascendente. Sin resultados → lista vacía `[]` (no error).

## 4. Qué debe devolver

Una fila por **línea de producto** de cada documento de devolución o anulación:

| Campo | Tipo | Descripción |
|---|---|---|
| `ReturnNumber` | string | Número del documento (`V78`, `VP232-1`…) |
| `ReturnType` | int | `70` devolución / void completo · `71` anulación parcial (`Facturas.Transaccion`) |
| `ReturnTypeName` | string | "Devolución" / "Anulación parcial" |
| `ReturnDate` | date | Fecha del documento |
| `ReturnTime` | string `HH:mm:ss` | Hora del documento |
| `LineID` | string | **Identificador estable y único** de la línea (ver §5.2) |
| `ItemCode` | string | `Inventario.Referencia` |
| `Description` | string | Descripción del artículo |
| `Quantity` | decimal | **Siempre positiva**: unidades que regresan |
| `Unit` | string | Unidad de medida (`UnidadID`); indicar si `Quantity` ya está en unidad base |
| `OriginalInvoice` | string | Factura que se devuelve/anula |
| `OriginalInvoiceDate` | date | **Fecha de la factura original** (`Facturas.Fecha`), null si no se puede resolver |
| `OriginalLineID` | string | Línea de la factura original, si se puede determinar (opcional) |
| `Customer` | string | `Facturas.Cliente` (`0000` = mostrador) |
| `CustomerName` | string | Nombre del cliente |
| `UserID` | string | Usuario/cajero que hizo la devolución |
| `Register` | string | Caja o cuadre (`CurrentCuadre`), si existe |
| `Reason` | string | Motivo/nota si RM lo guarda; vacío si no |
| `CreditNoteNumber` | string | Nota de crédito asociada (`NotaCreNum`), opcional |
| `IsService` | bool | `true` si el artículo es servicio (la app lo excluye) |
| `IsFuel` | bool | `true` si es combustible (la app lo excluye) |

### Ejemplo

```json
[
  {
    "ReturnNumber": "V78",
    "ReturnType": 70,
    "ReturnTypeName": "Devolución",
    "ReturnDate": "2026-10-28",
    "ReturnTime": "14:32:10",
    "LineID": "V78-3",
    "ItemCode": "AB-205-55R16",
    "Description": "LLANTA 205/55R16",
    "Quantity": 2.0,
    "Unit": "UN",
    "OriginalInvoice": "C10492",
    "OriginalInvoiceDate": "2026-10-21",
    "Customer": "0000",
    "CustomerName": "Cliente de mostrador",
    "UserID": "MARIA",
    "Register": "1",
    "Reason": "",
    "IsService": false,
    "IsFuel": false
  }
]
```

## 5. Reglas de negocio que el endpoint debe aplicar

1. **Fuente primaria:** documentos de `Facturas` con `Transaccion IN (70, 71)` y su detalle. `ARFile*`, `Merchant` y `Creditos` **no** deben generar filas (son duplicados financieros).
2. **`LineID` estable:** el mismo valor siempre para la misma línea, aunque se consulte de nuevo o cambie el rango. Debe ser único **dentro de toda la base** (idealmente `ID` del detalle, o `ReturnNumber` + secuencia). La app lo usa para no importar dos veces. **Debe ser el mismo `LineID` que entrega hoy `SalesInvoicesByDate` para esa línea**: mientras este endpoint no exista, la app lee las devoluciones de `SalesInvoicesByDate`, y si el valor cambia al pasar al endpoint nuevo, las devoluciones ya registradas se verían como nuevas.
3. **Sin doble conteo:** una anulación parcial (`VP`) puede aparecer a la vez como `FacturasDetalle.VoidParcial` en la línea original y como documento VP/`VoidDetalle`. Cada unidad devuelta debe aparecer **una sola vez**.
4. **Cantidad siempre positiva** (aplicar el mismo criterio de signo que `rpt.SalesLines`, pero entregando el valor absoluto de unidades físicas).
5. **Incluir histórico:** unir `Facturas`/`FacturasDetalle` con `FacturasHisto`/`FacturasDetalleHisto` para cubrir cualquier rango.
6. **Solo lectura**, sin efectos secundarios ni bloqueos largos (consulta con `NOLOCK`/aislamiento equivalente al resto de endpoints).
7. **Zona horaria:** fechas y horas en la hora local de la tienda, igual que `SalesInvoicesByDate`.
8. Incluir **todas** las líneas, también las de servicio y combustible (marcadas con `IsService`/`IsFuel`), para que el criterio de exclusión quede en la app.

## 6. Preguntas que el equipo de la API puede responder y que nos ahorran verificación

1. En las facturas `V`/`VP`, ¿la cantidad se guarda positiva o negativa en `FacturasDetalle.CantidadDespachada`?
2. ¿`VoidDetalle` es el detalle de los documentos `V`/`VP`, o guarda líneas quitadas en caja antes de cobrar?
3. Cuando RM procesa una devolución, ¿se descuenta `Inventario.Vendido` (el stock de RM sube)? ¿Y en una anulación parcial?
4. ¿Cómo se relaciona un documento `V`/`VP` con la factura original (campo o regla)? ¿Siempre existe?
5. ¿`Facturas.FechaCancelacion` y `Ordenes.FechaCancelacion` marcan cancelaciones o algo distinto?
6. ¿Existe un campo de **motivo** de devolución en RM?
7. ¿Hay devoluciones sin factura original (por ejemplo, de mostrador sin recibo)?

## 7. Alternativa mínima (si el endpoint completo se demora)

Agregar a `SalesInvoicesByDate` los campos **`OriginalInvoiceDate`** (`yyyy-MM-dd`) y `ReturnReason`, y garantizar `Quantity` positiva en `Transaccion` 70/71. La app ya lee esos dos campos si vienen (con esos nombres exactos). Con eso la app puede arrancar con la fuente actual mientras se construye el endpoint dedicado.

## 8. Compatibilidad y versión

- Endpoint **nuevo**; no cambia ninguno existente.
- Subir la versión (p. ej. 1.13.0) y exponerla en `HealthCheck`. La app trata un endpoint no disponible como "aún no disponible" y sigue funcionando con la fuente provisional.
- Funciona por tienda (cada empresa tiene su base, nombre por defecto `POSDPS`), igual que los demás.

## 9. Criterios de aceptación

1. Para un día con una devolución conocida, `SalesReturnsByDate` devuelve exactamente sus líneas, con `Quantity` positiva y `OriginalInvoice`/`OriginalInvoiceDate` correctos.
2. Una anulación parcial aparece **una vez** (no en la línea original y en el documento VP).
3. Dos llamadas idénticas devuelven los mismos `LineID`, y son iguales a los de `SalesInvoicesByDate` para las mismas líneas.
4. Un rango de 30 días se resuelve en una sola llamada y en tiempo razonable (< 10 s con el volumen actual).
5. Rango > 31 días → mismo error que `SalesInvoicesByDate`.
6. Rango sin devoluciones → `[]`.
7. Un documento antiguo que ya pasó a `FacturasHisto` también aparece.

## 10. Contacto

Carlos Omar — carlosomar@retailmanagerpr.com
