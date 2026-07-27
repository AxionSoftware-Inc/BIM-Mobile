# Tablet BIM — texnik handoff

Bu hujjat kontekst limiti yoki agent almashganda loyihani uzmasdan davom ettirish uchun yozilgan. Bu yerda aytilganlar koddagi amaldagi holatni bildiradi; marketing va'dasi emas.

## Mahsulot yo‘nalishi

Maqsad **"Revitning planshetdagi nusxasi"** emas. Maqsad — 12–14" Android/iPad planshet, stylus va ixtiyoriy klaviaturada ishlaydigan, offline-first, yengil arxitektura BIM authoring:

- ko‘p qavatli arxitektura modeli: level, wall, door, window, stair, floor, ceiling, flat roof;
- professional level constraint va authoritative save/reload;
- plan/elevation/3D, touch/stylus selection, drag, pan/orbit/zoom;
- keyinchalik IFC va PDF/documentation eksporti.

Ataylab V1 scope tashqarisida: MEP, murakkab Revit family ekotizimi, to‘liq konstruktsion hisob, slope/shape roof, og‘ir real-time clash/quantity compute va cloud collaboration.

## Arxitektura: source of truth

```
Flutter UI / tools / Inspector / temporary preview
                    │ FFI
                    ▼
C++ Engine API / transaction / validation / snapshot
                    │
                    ▼
C++ Document semantic model + dependency graph + persistence
                    │ snapshot mesh DTO
                    ▼
Filament native renderer (Android/macOS) yoki Flutter fallback (debug)
```

- **C++ engine authoritative**: production commit har doim enginega boradi. Flutter local editor faqat debug/demo/recovery uchun.
- **Flutter**: tool input, selection, preview, Inspector va native bridge. UI semantic modelni mustaqil saqlamasligi kerak.
- **Filament**: render va GPU resurslari; selection/interaction qoidasi Flutterda markaziy qoladi.
- **Snapshot**: engine har mutationdan keyin mesh + metadata snapshot beradi; UI yangi snapshotni chizadi.

Muhim fayllar:

- `src/core/src/Document.cpp` — semantic elementlar, geometry, level dependency, persistence hooks.
- `src/api/src/EngineApi.cpp` — engine snapshot va query API.
- `src/api/src/EngineCApi.cpp`, `src/api/include/tbe/api/EngineCApi.h` — Flutter uchun C ABI.
- `apps/viewer_flutter/lib/src/tbe_ffi.dart` — FFI va `ViewerRepository`.
- `apps/viewer_flutter/lib/src/tools/` — backenddan mustaqil tool controllerlar.
- `apps/viewer_flutter/lib/src/viewer_app.dart` — hozircha UI composition va tool adapterlar; yana kattalashmasligi kerak.
- `apps/viewer_flutter/android/app/src/main/kotlin/.../RenderSceneFilamentHostView.kt` — Android Filament renderer.

## Mavjud authoring oqimlari

Engine-first vertikal oqimlar:

- Wall: base/top level constraint bilan create, auto-join, snapshot.
- Door/window: host wall, level lock va vertical offset.
- Level: Inspector input va direct edit; siljiganda bog‘langan wall/opening/surface yangilanadi.
- Floor/ceiling/roof: profile transaction (rectangle/polyline/pick-wall; flat roof).
- Stair: straight-run V1. Base/top level, width, run, tread/riser count. Flutter `Stair` toolida ikki nuqta qo‘yiladi; top leveldan rise olinadi. Base yoki top level siljiganda stair rise va mesh qayta quriladi.

Stair cheklovi: hozircha straight run. L/U-shape, landing, railing, stair edit/type catalog keyingi milestone.

## Interaction qoidasi

`interaction` qoidasi barcha viewlarga bir xil selection state orqali tarqaladi:

- bo‘sh click / Esc selectionni tozalaydi;
- click active object qiladi; Ctrl/Shift multi-select;
- left-to-right rectangle contained, right-to-left crossing;
- desktop: empty-space drag navigate; tablet: bir barmoq orbit, ikki barmoq pan/zoom; long-press rectangle select;
- plan/elevation selected object direct-drag; 3D movement gizmo-only.

Renderer bu qarorlarni qabul qilmaydi; u `selected ids`, active id, rectangle va gizmo state’ni faqat ko‘rsatadi.

## Performance arxitekturasi

Hozir bor:

- nearby/active level snapshot policy;
- dirty element/level geometry recompute;
- immutable snapshotga mos compute pipeline yo‘nalishi;
- real 3/6/9 qavat benchmark fixturelari;
- Filament native renderer, adaptive idle render va telemetry UI;
- native visual styles: wire / solid / shaded.

Hali majburiy ish:

1. **Zone/level streaming**: katta bino faqat active + yaqin qavatlarni full meshda ushlashi; uzoq zone placeholder yoki LOD bo‘lishi.
2. **Instancing**: bir xil door/window/stair/type geometriyasi bitta GPU mesh + transform bilan. Hozir ko‘p obyekt alohida mesh bo‘lishi mumkin.
3. **Batching/material grouping**: draw-call sonini kamaytirish.
4. **LOD**: uzoqda facade/level shell, yaqinda to‘liq element mesh.
5. **Benchmark acceptance**: 3/6/9 qavat va detail-heavy scenario uchun cold load, snapshot, edit, save/reload, FPS, RAM, CPU va thermal yozuvi.

Muhim qoida: "GPU minimal" degani CPU render qilishi emas. Silliq viewportda GPU kam draw-call bilan chizadi; CPU doimiy full-model compute qilmaydi. Kamera tinch holatda render cadence pasaytiriladi. Og‘ir validation/schedule user so‘raganda yoki save/exportda bajariladi.

## Ko‘rilgan muammolar va sababi

### Level edit qiymati UI’da o‘zgarib, modelda o‘zgarmasligi

Sabab: Flutter text input/local preview va engine commit snapshotlari ajralib qolgan edi. Yechim: level edit engine transactionga bog‘landi, commitdan keyin authoritative snapshot qayta yuklanadi. Bu barcha future Inspector editlari uchun talab.

### Level ko‘chib, wall yoki opening ko‘chmasligi

Sabab: level relation metadata edi, lekin dependency/dirty propagation to‘liq emas edi; base/top constraint alohida yo‘llarda ishlardi. Yechim: `Document::move_level_elevation` barcha dependent elementlarni dirty qiladi va opening host/level constraintini sync qiladi.

### Opening cutout ko‘chib, door/window mesh eski joyda qolishi

Sabab: wall opening void va alohida door/window elementlari ikki geometry yo‘lidan kelgan. Yechim: host va opening vertical attachment bir transaction/level propagationda sync qilinadi. Kelajakda barcha hosted elementlar uchun shu contractdan chetga chiqmaslik kerak.

### Filamentda sahna 0 object, fallbackda model bor

Sabab: native `PlatformView` snapshot bridge va native library/asset yuklash lifecycle’i Flutter fallbackdan alohida edi. Yechim: renderer contract, runtime material bundle va native scene upload to‘g‘rilandi; macOS native runner qo‘shildi. Qoidasi: fallbackda ishlashi native rendererda ishlashini isbotlamaydi — native smoke test shart.

### Solid/wire/shaded bir xil yoki noto‘g‘ri ko‘rinishi

Sabab: Filament face material, edge overlay, depth va color grading bir-biridan ajralmagan edi. Wire real mesh edge bilan, shaded material bilan, solid oq BIM face + visible edge policy bilan ajratildi. Hali UX/visual tuning davom etadi.

### Orbitda model pirpirashi yoki qismlari yo‘qolishi

Sabab: bounds double-transform/culling va camera near/far plane noto‘g‘ri edi. Fit camera/culling bounds tuzatildi. Katta modelda qaytarsa: world bounds, camera near/far, depth precision va edge overlay z-fightingni birga tekshirish kerak.

### Android wall commit previewdan keyin yo‘qolishi

Sabab: touch gesture finish, coordinate conversion, FFI commit va snapshot refresh qaysi nuqtada uzilganini bilish qiyin edi. Yechim: Android mutation trace (tap screen → model point → levels → created wall ID → snapshot count) kiritildi. Bunday muammolar uchun avval observability, keyin taxmin emas.

## Hozirgi qarorlar va ehtiyot bo‘ladigan joylar

- `ViewerApp` hali katta. Tool controllerlar ajratilgan, ammo keyingi katta ishda `ToolCoordinator`/command adapterga bo‘lish kerak.
- Eski `RenderSceneEditor` fallback production mutatsiya qilmasligi kerak. Yangi object tool engine API’siz qo‘shilmasin.
- User worktree’da quyidagi untracked fayllar bo‘lishi mumkin; ularga tegmang: `docs/architecture_blockers_uz.md`, `docs/project_overview_uz.md`.
- Android va macOS renderer parity har visual/interaction feature uchun tekshirilsin.
- `wall`, `door/window`, `floor/ceiling/roof`, `stair`ning hammasi level binding metadata’siz yaratilmasin.

## Keyingi roadmap

1. Stair V1 smoke: Android/macOS’da create → level move → save/reload → select/Inspector.
2. Stair V1.1: landing va L/U-shape (bitta transaction profilidan); railing keyin.
3. Performance renderer module: streaming, LOD, instancing, batch/material cache.
4. Real 30 qavat architecture benchmark: faqat model, ichki bezaksiz; 8 GB RAM va 12 GB RAM qurilmalarda o‘lchash.
5. Floor/ceiling/roof level contractini stair darajasida uniform qilish.
6. IFC import/export, PDF sheet/documentation.

## Qabul mezoni

30+ qavat architecture model uchun maqsad: tablet qizib ketmasdan plan/3D navigation va basic edit. Bu "hamma qavatni full detail bilan bir vaqtda GPUga yuklash" emas. Qabul testida active/nearby levellar full, uzoq level/zone LOD yoki streamingda bo‘ladi; save/reload relationlarni yo‘qotmaydi; og‘ir final compute faqat explicit so‘rovda ishlaydi.
