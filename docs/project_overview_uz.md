# BIM-Mobile Loyiha Sharhi

## 1. Loyiha maqsadi

`BIM-Mobile` bu C++20 asosidagi, cross-platform, engine-first BIM/CAD yadrosi va uning ustiga qurilayotgan Flutter viewer/editor loyihasi.

Asosiy maqsad:

- bitta kuchli yadro bilan `macOS`, `Windows`, `Android`, `iPad`, keyinroq `cloud worker` muhitlarini ishlatish
- UI'ni yadrodan qat'iy ajratish
- avval semantic BIM modelni to'g'ri qilish, keyin rendering va interaction qatlamini ulash
- Revitga o'xshash ish oqimini soddalashtirilgan, lekin toza arxitektura bilan berish

Hozirgi yo'nalish:

- engine semantic source of truth
- Flutter faqat interaction + viewport + inspector qatlami
- `RenderScene` viewer uchun barqaror ko'prik
- draw/edit/level/view logikasi imkon qadar engine tarafga tushirilmoqda

---

## 2. Loyiha falsafasi

Loyiha quyidagi tamoyillarga tayanadi:

- `engine-first`: modelni UI emas, yadro boshqaradi
- `cross-platform core`: OCCT bo'lmasa ham ishlaydigan portable fallback geometry
- `semantic before visual`: devor, level, opening, room, floor, ceiling, roof avval semantic to'g'ri bo'lishi kerak
- `single-source rendering bridge`: viewer `debug_report` yoki ad-hoc OBJ emas, `RenderScene` bilan ishlashi kerak
- `unified drawing logic`: wall/floor/ceiling/roof uchun chizish mantig'i bitta kernel asosida yurishi kerak

---

## 3. Yuqori darajadagi arxitektura

Loyiha 4 ta asosiy qatlamga bo'linadi:

### 3.1 Core engine

Manzil:

- `src/core/include/tbe/core`
- `src/core/src`

Vazifasi:

- semantic elementlar modeli
- level, wall, door, window, room, slab, floor, ceiling, roof, column, beam, stair
- dependency/freshness/validation
- save/load, migration, repair
- schedules, takeoff, room metrics
- fallback mesh generation
- `RenderScene` export

Bu qatlam UI bilmaydi.

### 3.2 Public API / C ABI

Manzil:

- `src/api/include/tbe/api`
- `src/api/src`

Vazifasi:

- core'ni stable API orqali tashqariga chiqarish
- C++ API
- C ABI / FFI-safe boundary
- session, load/save, create/edit commands, validation, export

Bu qatlam Flutter kabi clientlar uchun kirish nuqtasi.

### 3.3 Developer tools / CLI

Manzil:

- `apps/tbe_cli`
- `examples`
- `tests`

Vazifasi:

- smoke test
- torture test
- package/export check
- API demo
- regression verification

### 3.4 Flutter viewer/editor

Manzil:

- `apps/viewer_flutter`

Vazifasi:

- 2D/3D viewport
- object selection
- draft preview
- engine-backed create/edit oqimi
- level/elevation/view interaction

Muhimi: Flutter semantic source of truth emas.

---

## 4. Semantic modelning markazi

Hozirgi engine quyidagi asosiy semantic obyektlar bilan ishlaydi:

- `Level`
- `Wall`
- `Door`
- `Window`
- `Room`
- `Slab`
- `FloorSystem`
- `CeilingSystem`
- `Roof`
- `Column`
- `Beam`
- `Stair`
- `Material`
- `WallType / Assembly`

Muhim bog'lanishlar:

- wall levelga bog'lanadi
- door/window host wallga bog'lanadi
- room wall boundary'dan hosil bo'ladi
- floor/ceiling/roof level va profile boundary bilan ishlaydi
- geometry authoritative emas, semantic model authoritative

---

## 5. Render oqimi

Render oqimi hozir quyidagicha:

1. Engine semantic modelni ushlab turadi
2. Derived geometry fallback mesh ko'rinishida generatsiya qilinadi
3. Engine `RenderScene` eksport qiladi
4. Flutter `RenderScene` ni parse qiladi
5. Viewport 2D/3D ko'rinishlarni shu umumiy sahnadan oladi

Bu juda muhim:

- 2D va 3D alohida-alohida sahna bo'lmasligi kerak
- ular bitta modelning turli projection/view ko'rinishi bo'lishi kerak

---

## 6. Level va view kontseptsiyasi

Loyihadagi to'g'ri model:

- `View` sahnani ko'rish usuli
- `Level` esa semantic anchor

Demak:

- level yangi sahna yaratmaydi
- level obyektlarni filtrlaydi, constraint beradi, elevation beradi
- plan/elevation/3D bitta modelni boshqa nuqtadan ko'rsatadi

Kelajakdagi toza holat:

- level select qilinadi
- elevation edit qilinadi
- wall base/top level constraint bilan boshqariladi
- opening host wall orqali vertical lock oladi
- floor/ceiling/roof level bilan authoritative ishlaydi

---

## 7. Chizish arxitekturasi

Loyihaning muhim uzoq muddatli maqsadi:

`wall`, `floor`, `ceiling`, `roof` uchun alohida draft logika yozib ketmaslik.

Shuning uchun unified drawing kernel yo'nalishi tanlangan:

- `Polyline`
- `Rectangle`
- `PickWalls`
- keyinroq `AutoRoom`

Targetlar:

- `WallPath`
- `FloorBoundary`
- `CeilingBoundary`
- `RoofBoundary`

Prinsip:

- Flutter nuqtalar/wall pick'larni yig'adi
- engine profile draft'ni normalize va validate qiladi
- create semantic object engine tarafda bo'ladi

Bu yondashuv keyingi kengaytirishlarni osonlashtiradi.

---

## 8. Hozirgi real holat

Loyiha kuchli demo bosqichiga yaqinlashgan, lekin hali final emas.

Nisbatan tayyor qismlar:

- semantic engine foundation
- API/C ABI
- save/load/schema/migration asoslari
- validation/schedule/takeoff
- RenderScene bridge
- Flutter viewport va interaction skeleton

Hali kuchaytiriladigan joylar:

- level select/edit UX va engine sync
- wall base/top constraint flow
- unified surface drawing UX
- arbitrary shape floor/ceiling/roof draw oqimi
- room auto-detect limitationlari
- fallback geometry join/cut sifatini yaxshilash

---

## 9. Papkalar xaritasi

### Root

- `CMakeLists.txt`
  - asosiy CMake entry point
- `cmake/`
  - build helper modullar
- `docs/`
  - texnik hujjatlar
- `scripts/`
  - umumiy yordamchi scriptlar

### Core

- `src/core/include/tbe/core/`
  - public core headers
- `src/core/src/`
  - core implementation

Asosiy fayllar:

- `src/core/include/tbe/core/Document.hpp`
  - hujjat modeli va asosiy engine surface
- `src/core/include/tbe/core/Element.hpp`
  - element turlari va semantic strukturalar
- `src/core/src/Document.cpp`
  - ko'p command/create/detect/recompute logika shu yerda
- `src/core/src/DocumentJson.cpp`
  - save/load/migration bilan bog'liq JSON oqimi
- `src/core/src/GeometryService.cpp`
  - fallback geometry / mesh xizmatlari

### API

- `src/api/include/tbe/api/EngineApi.hpp`
  - public C++ API
- `src/api/include/tbe/api/EngineCApi.h`
  - C ABI
- `src/api/src/EngineApi.cpp`
  - API implementation
- `src/api/src/EngineCApi.cpp`
  - FFI-safe bridge implementation

### Tests

- `tests/core_tests.cpp`
  - core semantic va geometry regressions
- `tests/api_tests.cpp`
  - API layer regressions

### CLI

- `apps/tbe_cli`
  - local demo, torture, export, validation CLI

### Flutter

- `apps/viewer_flutter/lib/main.dart`
  - Flutter entry point
- `apps/viewer_flutter/lib/src/viewer_app.dart`
  - viewer/editor shell, toolbar, inspector, state orchestration
- `apps/viewer_flutter/lib/src/tbe_ffi.dart`
  - Dart -> C API bridge
- `apps/viewer_flutter/lib/src/render_scene_models.dart`
  - RenderScene DTO parser/model
- `apps/viewer_flutter/lib/src/render_scene_repository.dart`
  - scene load source abstraction
- `apps/viewer_flutter/lib/src/render_scene_editor.dart`
  - vaqtinchalik local preview/helper qatlam
- `apps/viewer_flutter/lib/src/render_scene_viewport_controller.dart`
  - viewport state, camera, selection, draft state
- `apps/viewer_flutter/lib/src/render_scene_viewport_widget.dart`
  - viewport widget
- `apps/viewer_flutter/lib/src/render_scene_viewport_painter.dart`
  - Flutter fallback canvas renderer
- `apps/viewer_flutter/lib/src/render_scene_viewport_projection.dart`
  - 2D/3D projection matematikasi
- `apps/viewer_flutter/lib/src/render_scene_level_overlay.dart`
  - level line draw/hit logic

### Next.js reference viewer

- `apps/viewer_next`
  - eski/reference/debug viewer
  - asosiy product UI yo'li endi Flutter

---

## 10. Muhim hujjatlar

Tez orientatsiya uchun:

- `docs/engine_mvp_architecture.md`
  - engine tarixiy MVP yo'nalishi
- `docs/render_scene.md`
  - RenderScene contract
- `docs/projection_view_architecture.md`
  - 2D/3D/elevation/view mantig'i
- `docs/filament_renderer_plan.md`
  - keyingi native renderer yo'nalishi
- `docs/engine_robustness.md`
  - robustness va cheklovlar
- `docs/core_v0_1_limitations.md`
  - nimalar hali cheklangan

---

## 11. Yaqin maqsad

Yaqin milestone quyidagilarni mustahkamlashi kerak:

- level select va edit real ishlashi
- wall base/top level constraint engine-backed bo'lishi
- floor/ceiling/roof draw unified kernel orqali ishlashi
- non-rectangular house layout uchun floor/ceiling draw ishlashi
- Flutter local mutation emas, engine command path authoritative bo'lishi

Natija:

oddiy uycha, L-shaped xona, bir nechta level, floor/ceiling/roof, door/window bilan demo darajada ishonchli BIM oqimi.

---

## 12. Qisqa xulosa

Bu loyiha oddiy viewer emas.

Bu:

- semantic BIM engine
- stable API boundary
- shared render bridge
- Flutter-first future UI

ga tayangan, keyinchalik professional tablet/desktop BIM workflow'ga aylantiriladigan yadro hisoblanadi.

Hozir eng muhim vazifa:

`arxitektura tozaligi + semantic aniqlik + bitta yadrodan ko'p view`.
