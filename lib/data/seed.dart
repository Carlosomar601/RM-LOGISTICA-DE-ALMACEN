import '../models/app_user.dart';
import '../models/inv_row.dart';
import '../models/movement.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/receipt.dart';
import '../models/store_transfer.dart';
import '../util/clock.dart';

const kCentral = 'Almacén Central';

const kStores = <String>[
  'Almacén Central',
  'Sucursal Río Piedras',
  'Sucursal Bayamón',
  'Sucursal Ponce',
];

const kAllBins = <String>[
  'A-01-01', 'A-01-02', 'A-01-03', 'A-01-04', 'A-02-01', 'A-02-02',
  'A-03-01', 'A-03-02', 'A-03-03', 'B-01-01', 'B-01-02', 'B-02-01',
  'B-02-02', 'B-03-01', 'B-03-02', 'B-03-03', 'C-01-01', 'C-01-02',
  'C-02-01', 'C-03-02', 'RECIBO',
];

const kSuppliers = <String>[
  'Michelin PR Distribuidora',
  'Goodyear Caribe',
  'Bridgestone Antillas',
  'Continental Import PR',
  'Pirelli Borinquen',
];

const kCustomers = <String>[
  'Llantas del Norte',
  'Frenos y Gomas Vega',
  'AutoCentro Caparra',
  'Taller Los Amigos',
  'Gomas Express Manatí',
];

/// Umbrales de antigüedad.
const kAgeAlertDays = 45;
const kStaleDays = 180;

List<Product> seedProducts() => [
      Product(id: 'p1', code: 'MI-20565R15', desc: 'Michelin Primacy 4 · 205/65R15', committed: 6),
      Product(id: 'p2', code: 'GY-19565R15', desc: 'Goodyear Assurance CS · 195/65R15', committed: 4),
      Product(id: 'p3', code: 'BS-22545R17', desc: 'Bridgestone Turanza T005 · 225/45R17', committed: 0),
      Product(id: 'p4', code: 'MI-23555R18', desc: 'Michelin CrossClimate2 · 235/55R18', committed: 2),
      Product(id: 'p5', code: 'CO-17570R13', desc: 'Continental ContiPowerContact · 175/70R13', committed: 0),
      Product(id: 'p6', code: 'FI-20555R16', desc: 'Firestone Destination LE2 · 205/55R16', committed: 5),
      Product(id: 'p7', code: 'GY-26570R16', desc: 'Goodyear Wrangler AT/SA · 265/70R16', committed: 0),
      Product(id: 'p8', code: 'BS-18565R14', desc: 'Bridgestone Ecopia EP150 · 185/65R14', committed: 3),
      Product(id: 'p9', code: 'PI-21560R16', desc: 'Pirelli Scorpion Verde · 215/60R16', committed: 0),
      Product(id: 'p10', code: 'MI-16580R14', desc: 'Michelin Energy XM2 · 165/80R14', committed: 0),
    ];

List<InvRow> seedInventory() {
  const ac = kCentral;
  const rp = 'Sucursal Río Piedras';
  const sb = 'Sucursal Bayamón';
  const sp = 'Sucursal Ponce';
  // (product, store, bin, qty, ageDays, receipt, lot, user)
  final raw = <(String, String, String, int, int, String, String, String)>[
    ('p1', ac, 'A-01-01', 14, 52, 'REC-3301', 'L-2208', 'M. Rivera'),
    ('p1', ac, 'A-01-02', 20, 31, 'REC-3358', 'L-2231', 'M. Rivera'),
    ('p1', ac, 'B-02-01', 18, 9, 'REC-3402', 'L-2266', 'J. Nieves'),
    ('p1', sp, 'SP-01', 6, 17, 'REC-3379', 'L-2244', 'L. Cruz'),
    ('p2', ac, 'A-01-03', 10, 40, 'REC-3320', 'L-2214', 'M. Rivera'),
    ('p2', ac, 'B-01-01', 22, 6, 'REC-3410', 'L-2270', 'J. Nieves'),
    ('p3', ac, 'C-03-02', 8, 61, 'REC-3260', 'L-2179', 'M. Rivera'),
    ('p3', ac, 'A-02-01', 12, 24, 'REC-3365', 'L-2236', 'J. Nieves'),
    ('p3', rp, 'RP-04', 4, 12, 'REC-3389', 'L-2251', 'A. Torres'),
    ('p4', ac, 'A-02-02', 5, 3, 'REC-3418', 'L-2275', 'J. Nieves'),
    ('p4', ac, 'RECIBO', 9, 1, 'REC-3421', 'L-2277', 'J. Nieves'),
    ('p5', ac, 'B-02-02', 16, 28, 'REC-3350', 'L-2226', 'M. Rivera'),
    ('p5', ac, 'C-02-01', 6, 195, 'REC-3120', 'L-2050', 'M. Rivera'),
    ('p6', ac, 'A-01-04', 7, 47, 'REC-3298', 'L-2205', 'M. Rivera'),
    ('p6', ac, 'B-01-02', 11, 15, 'REC-3392', 'L-2255', 'J. Nieves'),
    ('p6', sb, 'SB-02', 5, 8, 'REC-3405', 'L-2267', 'R. Ortiz'),
    ('p7', ac, 'C-01-01', 6, 35, 'REC-3335', 'L-2219', 'M. Rivera'),
    ('p7', ac, 'C-01-02', 4, 250, 'REC-3055', 'L-1998', 'M. Rivera'),
    ('p8', ac, 'A-03-01', 14, 55, 'REC-3272', 'L-2188', 'M. Rivera'),
    ('p8', ac, 'A-03-02', 10, 5, 'REC-3413', 'L-2272', 'J. Nieves'),
    ('p8', ac, 'A-03-03', 8, 210, 'REC-3096', 'L-2018', 'M. Rivera'),
    ('p9', sp, 'SP-03', 4, 18, 'REC-3382', 'L-2247', 'L. Cruz'),
    ('p10', ac, 'B-03-01', 20, 22, 'REC-3368', 'L-2239', 'J. Nieves'),
    ('p10', ac, 'B-03-02', 9, 2, 'REC-3419', 'L-2276', 'J. Nieves'),
    ('p10', ac, 'B-03-03', 3, 300, 'REC-2988', 'L-1935', 'J. Nieves'),
  ];
  var i = 1;
  return [
    for (final r in raw)
      InvRow(
        id: 'inv-${i++}',
        productId: r.$1,
        store: r.$2,
        bin: r.$3,
        qty: r.$4,
        entryDate: daysAgo(r.$5),
        receipt: r.$6,
        lot: r.$7,
        user: r.$8,
      ),
  ];
}

/// Siguiente id de inventario tras el seed.
const kSeedInvCount = 25;

List<Order> seedOrders() => [
      Order(
        id: 'OV-10501',
        customer: 'AutoExpress Caguas',
        store: 'Sucursal Río Piedras',
        date: kToday,
        status: 'pendiente',
        items: [
          OrderItem(productId: 'p1', qty: 4),
          OrderItem(productId: 'p3', qty: 15),
          OrderItem(productId: 'p6', qty: 10),
        ],
      ),
      Order(
        id: 'OV-10502',
        customer: 'Taller Hermanos Ortiz',
        store: 'Sucursal Bayamón',
        date: kToday,
        status: 'pendiente',
        items: [
          OrderItem(productId: 'p2', qty: 6),
          OrderItem(productId: 'p9', qty: 3),
        ],
      ),
      Order(
        id: 'OV-10503',
        customer: 'Gomas Rivera',
        store: 'Sucursal Ponce',
        date: daysAgo(1),
        status: 'pendiente',
        items: [
          OrderItem(productId: 'p4', qty: 3),
          OrderItem(productId: 'p8', qty: 5),
          OrderItem(productId: 'p10', qty: 4),
        ],
      ),
    ];

List<Receipt> seedReceipts() => [
      Receipt(
        id: 'REC-3430',
        supplier: 'Michelin PR Distribuidora',
        date: kToday,
        items: [ReceiptItem(productId: 'p1', qtyReceived: 100)],
      ),
      Receipt(
        id: 'REC-3431',
        supplier: 'Goodyear Caribe',
        date: kToday,
        items: [
          ReceiptItem(productId: 'p2', qtyReceived: 40),
          ReceiptItem(productId: 'p7', qtyReceived: 20),
        ],
      ),
      Receipt(
        id: 'REC-3432',
        supplier: 'Bridgestone Antillas',
        date: daysAgo(1),
        items: [ReceiptItem(productId: 'p6', qtyReceived: 30, qtyAllocated: 10)],
      ),
    ];

/// Historial semilla, del más reciente al más antiguo.
List<Movement> seedHistory() {
  String loc(String bin) => '$kCentral / $bin';
  final raw = <(int, int, int, String, String, int, String, String, String, String)>[
    // (díasAtrás, hora, min, tipo, producto, cant, doc, desde, hacia, usuario)
    (1, 16, 40, 'entrada', 'p4', 9, 'REC-3421', '—', loc('RECIBO'), 'J. Nieves'),
    (2, 10, 15, 'entrada', 'p10', 9, 'REC-3419', '—', loc('B-03-02'), 'J. Nieves'),
    (3, 15, 30, 'piqueo', 'p1', 4, 'OV-10460', loc('A-01-01'), 'Despacho', 'C. Omar'),
    (4, 11, 20, 'transfer-bin', 'p6', 3, 'TB-2201', loc('B-01-02'), loc('A-01-04'), 'J. Nieves'),
    (5, 9, 45, 'entrada', 'p8', 10, 'REC-3413', '—', loc('A-03-02'), 'J. Nieves'),
    (6, 14, 10, 'piqueo', 'p2', 5, 'OV-10441', loc('A-01-03'), 'Despacho', 'C. Omar'),
    (7, 17, 5, 'ajuste', 'p5', -2, 'AJ-0091', loc('B-02-02'), '—', 'M. Rivera'),
    (8, 10, 30, 'transfer-store-out', 'p6', 5, 'TS-0088', kCentral, 'Sucursal Bayamón', 'J. Nieves'),
    (8, 10, 30, 'transfer-store-in', 'p6', 5, 'TS-0088', kCentral, 'Sucursal Bayamón', 'R. Ortiz'),
  ];
  var seq = 1000 + raw.length - 1;
  return [
    for (final r in raw)
      Movement(
        id: 'MV-${seq--}',
        type: r.$4,
        productId: r.$5,
        qty: r.$6,
        doc: r.$7,
        user: r.$10,
        dateTime: daysAgo(r.$1, hour: r.$2, minute: r.$3),
        from: r.$8,
        to: r.$9,
      ),
  ];
}

List<StoreTransfer> seedStoreTransfers() => [
      StoreTransfer(
        id: 'TS-0088',
        productId: 'p6',
        qty: 5,
        fromStore: kCentral,
        toStore: 'Sucursal Bayamón',
        sentAt: daysAgo(8, hour: 10, minute: 30),
        status: 'recibido',
        receivedAt: daysAgo(8, hour: 10, minute: 30),
      ),
    ];

List<BinTransfer> seedBinTransfers() => [
      BinTransfer(
        id: 'TB-2201',
        productId: 'p6',
        qty: 3,
        from: 'B-01-02',
        to: 'A-01-04',
        user: 'J. Nieves',
        dateTime: daysAgo(4, hour: 11, minute: 20),
        obs: '—',
      ),
    ];

List<AppUser> seedUsers() => [
      AppUser(
        id: 'u1',
        name: 'Carlos Omar',
        email: 'carlosomar@retailmanagerpr.com',
        role: 'Administrador',
        active: true,
        perms: rolePreset('Administrador'),
      ),
      AppUser(
        id: 'u2',
        name: 'María Rivera',
        email: 'mrivera@centenotire.com',
        role: 'Supervisor de almacén',
        active: true,
        perms: rolePreset('Supervisor de almacén'),
      ),
      AppUser(
        id: 'u3',
        name: 'Juan Nieves',
        email: 'jnieves@centenotire.com',
        role: 'Piqueador',
        active: true,
        perms: rolePreset('Piqueador'),
      ),
      AppUser(
        id: 'u4',
        name: 'Luis Cruz',
        email: 'lcruz@centenotire.com',
        role: 'Recibidor',
        active: false,
        perms: rolePreset('Recibidor'),
      ),
    ];
