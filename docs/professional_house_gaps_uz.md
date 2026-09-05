# Professional Courtyard Villa — real loyiha uchun funksional bo'shliqlar

Bu hujjat `Professional Courtyard Villa · 2 Storey` starter loyihasini ishlab
chiqish bilan birga yuritiladi. Template professional ko'rinishdagi ishchi
namuna: u real BIM loyihasining tayyor konstruktiv yoki ishchi hujjat o'rnini
bosmaydi. Quyidagi ro'yxat dekorativ wishlist emas — haqiqiy uy loyihasini
chizish, tekshirish, hujjatlashtirish va qayta ishlash uchun kerak bo'ladigan
funksiyalardir.

## Hozirgi template nimalarni ko'rsatadi

- `Level 1`, `Level 2` va alohida `Roof` leveli, devorlarning top-level
  constraint'lari va levelga bog'langan openinglar.
- Markaziy hall, kitchen/service zonalari, yotoq xonalari va ikki qavatda
  qayta ishlatilgan interior/exterior wall type'lar.
- Brick-based `Exterior Wall`, `Interior Wall`, wood floor assembly,
  ceiling, foundation, 25° automatic footprint roof va 0.60 m overhang.
- Bir dona haqiqiy silliq curved entrance facade; u mayda straight wall'lar
  yig'indisi emas.
- L-shaped stair, landing va railing flag'i, structural column/beam hamda
  floor/ceiling elementlari.
- Grass, asphalt driveway, paving walkway va patio bir-birining ustiga
  coplanar tushmaydigan site datum'larida.
- Family reference bilan joylashtirilgan reusable content: sofa, dining table,
  kitchen cabinet, refrigerator, storage cabinet, double/single bed, column,
  toilet, vanity va bathtub.
- `Wall Sweep · Horizontal Belt` family: tanlangan devorga host qilinadi,
  devor yo'nalishiga mos aylanadi, devor bo'ylab masofasi va asosiy o'lchamlari
  joylashtirish oynasidan/Inspector'dan boshqariladi; 2D symbol ham shu
  yo'nalishni saqlaydi.

## Real ish uchun hali kerak bo'ladigan funksiyalar

### 1. Geometrik va arxitektura authoring

- Floor va ceiling boundary'larini curved wall, arc segment, hole/shaft va
  bir nechta loop bilan chizish; hozirgi profile path asosan oddiy polygon va
  room-bound oqimiga tayanadi.
- Wall join'larda murakkab T/Y/X kesishmalar, compound-layer wrap, reveal,
  end-cap va curved-to-straight transition'larni bir xil qat'iy natijada
  hisoblash.
- Door/window'ni wall-hosted family sifatida rotation, flip, sill/head
  constraint, nested frame va opening reveal bilan boshqarish; opening
  geometriyasi bilan family ko'rinishi alohida bo'lib qolmasligi kerak.
- Room separation line, shaft opening, void/cutter va double-height room'ni
  birinchi darajali authoring obyektlari qilish.

### 2. Stair va roof editing

- Straight/L/U stair'ni keyin ham tutqichlardan tahrirlash: riser/tread,
  landing o'lchami, flight yo'nalishi, railing balandligi va handrail profili.
- Stair opening'ni floor system bilan avtomatik bog'lash va qavat almashtirish
  paytida opening'ni buzmaslik.
- Roof sketch, ridge/valley/hip, multi-slope roof, dormer, gutter, fascia,
  parapet va roof-to-wall intersection'larini edit qilish.
- Roof slope va overhang o'zgarganda devor, fascia va drainage chetlarining
  avtomatik qayta hisoblanishi.

### 3. Family va constraint tizimi

- Face-hosted, level-based va non-hosted placement turlarini yagona placement
  contract'ga kiritish; wall-hosted contract hozir opening va wall sweep uchun
  umumiy host centerline query'lari bilan ishlaydi.
- Family instance uchun rotate/flip, host almashtirish, alignment, array,
  lock/equality constraint va type catalog'ni saqlash.
- Nested family, shared parameter, formula, visibility/detail-level va
  type-vs-instance parameter'larini to'liq ajratish.
- Family preview, plan SVG va native 3D mesh bitta family type'dan hosil
  bo'lishi; 2D yengil ko'rinish 3D modelning tasodifiy nusxasiga aylanmasligi.

### 4. Structure va MEP koordinatsiyasi

- Column/beam'larni structural system va analytical model bilan bog'lash,
  framing join va load-bearing tasnifini saqlash.
- Foundation wall, footing, slab edge, retaining wall va site grade'ni
  boshqarish.
- Sanitary, water, HVAC, electrical va drainage uchun route, fitting,
  terminal, shaft va equipment oilalari.
- MEP opening'larini structural wall/floor bilan clash tekshiruviga yuborish.

### 5. Site va real qurilish tayyorgarligi

- Qiya topography, spot elevation, contour, retaining wall, drainage slope,
  parking/curb va site boundary.
- Material qatlamlari uchun finish/core/insulation semantics, opening atrofida
  wrap va quantity takeoff'da to'g'ri net/gross hisob.
- Phase, design option, demolition/new-work va temporary construction state.
- Real qurilishdagi revision, issue, approval va change tracking oqimi.

### 6. Hujjat va tekshiruv

- Dimension, aligned/linear/angular/spot dimension, level marker, room tag,
  door/window tag, material tag va north arrow.
- View template, crop region, detail level, hidden-line priority, section/elevation
  marker va sheet/title block.
- Door/window/room/material/family schedule, calculated fields, filtering,
  sorting va schedule export.
- Model validation: orphan opening, unjoined wall, duplicate type, invalid
  host, unsupported family, room leak, roof gap va level constraint warning'lari.
- Atomic undo/redo va save/reload testlari barcha authoring oqimlarida;
  xato parametr avvalgi valid holatga qaytishi kerak.

### 7. Ishlash sifati va katta loyiha

- 30 qavat, minglab wall instance va o'n minglab family instance bilan
  benchmark: first frame, pan/zoom, selection, edit, save/reload, RAM,
  frame-drop va qurilma qizishi.
- Bir xil family type'lar uchun instancing va spatial culling; har bir
  instance alohida og'ir native mesh saqlamasligi.
- 2D plan uchun symbol cache, 3D uchun level/viewport LOD va dirty-region
  recompute. Bitta nuqta o'zgarganda butun scene reload qilinmasligi.
- Deterministic fallback va native renderer natijalarini bir xil semantic
  modelga yaqinlashtirish; curved wall uchun alohida regression testlar.

### 8. Keyinroq qilinadigan almashuv formatlari

IFC import/export hozirgi authoring scope'ining markazi emas. Keyingi bosqichda
IFC round-trip, RVT/DWG kabi formatlarning mapping'i, units, materials,
families, phases va unsupported-feature report'i alohida acceptance test bilan
qo'shiladi. Bu ish iOS portidan ham oldin model semantics'i barqaror bo'lishini
talab qiladi.

## Tavsiya etiladigan ketma-ketlik

1. Wall/opening/room constraint va validation'ni yakunlash.
2. Curved/freeform floor-ceiling va roof/stair editing'ni bir xil profile
   contract'ga o'tkazish.
3. Family hosting, type/instance parameter va placement/move oqimini tugatish.
4. Structure + MEP openings/clash check'ni qo'shish.
5. Dimension/tag/schedule/sheet hujjat qatlamini chiqarish.
6. 30 qavat benchmark va instancing/culling optimizatsiyasidan keyin format
   import/export'ini acceptance test bilan ochish.

Har bir bosqich uchun “template ochildi”ning o'zi yetarli mezon emas: yangi
loyiha, saqlash-qayta ochish, level almashtirish, 2D/3D almashish, select/move,
invalid parameter va undo/redo alohida tekshiriladi.
