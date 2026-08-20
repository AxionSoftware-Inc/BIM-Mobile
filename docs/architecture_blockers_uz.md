# BIM-Mobile Arxitektura Muammolari Va Nega Oldinga Siljish Sekinlashdi

## Qisqa javob

Biz oldinga sekinlashib qoldik, chunki loyiha bir vaqtning o'zida ikki yo'nalishda yashab qoldi:

- `engine-first` toza arxitektura qurilyapti
- lekin Flutter viewer ichida hali ham vaqtinchalik local authoring/fallback logika yashab turibdi

Natijada:

- semantic source of truth ba'zan engine, ba'zan viewer bo'lib qolyapti
- level, wall constraint, room/floor/ceiling behavior bir joyda emas, ikki joyda yashayapti
- UI'dagi xatoni tuzatish uchun qilingan tezkor patch keyin engine logikasi bilan urishib qoladi
- yangi feature qo'shilganda kod ko'payadi, lekin sistemaning markazi soddalashmaydi

Shuning uchun muammo kod yozilmayotganida emas.
Muammo: arxitektura markazi hali to'liq bitta oqimga tushmagan.

---

## 1. Asosiy root cause

### 1.1 Ikki xil source of truth bor

Engine tarafda semantic model bor:

- `src/core/src/Document.cpp`
- `src/api/src/EngineApi.cpp`
- `src/api/include/tbe/api/EngineApi.hpp`

Lekin viewer tarafda ham hali local mutation va normalization mavjud:

- `apps/viewer_flutter/lib/src/render_scene_editor.dart`

Ayniqsa shu joylar signal beradi:

- `normalizeSceneGeometry`
- `createLevel`
- `setLevelElevation`
- `addWall`
- `addDoor`
- `addWindow`
- `synchronizeAutoRoomSurfaces`

Bu metodlar demo tez yurishi uchun foydali bo'lgan, lekin endi arxitektura qarziga aylangan.

Muammo:

- engine semantic element yaratadi
- viewer ham local render scene ni qayta quradi
- ikkalasi bir xil narsani ikki xil joyda "to'g'rilashga" urinyapti

Natijada:

- bug qayerdan kelganini topish qiyin
- level, room, floor, ceiling xatti-harakati bir xil chiqmaydi
- bir joydagi fix boshqa joyda aks etmaydi

---

## 2. Hozirgi eng katta arxitektura muammolari

### 2.1 Unified drawing kernel hali to'liq markazlashmagan

Engine tarafda profile-based create API allaqachon bor:

- `create_elements_from_profile`
- `ProfileDraftDTO`
- `ApiProfileDraftMode`
- `PickWalls`
- `AutoRoom`

Manzillar:

- `src/api/include/tbe/api/EngineApi.hpp`
- `src/api/src/EngineApi.cpp`
- `src/core/include/tbe/core/Document.hpp`
- `src/core/src/Document.cpp`

Lekin real product oqimi hali to'liq shu yo'ldan yurmayapti.

Sababi:

- Flutter ichida alohida wall draft state bor
- alohida floor/ceiling preview state bor
- alohida opening preview state bor
- ba'zi oqimlarda engine command ishlaydi, ba'zilarida local helper ishlaydi

To'g'ri yakuniy model:

- Flutter faqat draft input yig'adi
- barcha create wall/floor/ceiling/roof commit engine API orqali o'tadi
- wall/floor/ceiling/roof draw uchun bitta drawing kernel ishlaydi

Hozir esa bu to'liq tugamagan.

### 2.2 Level semantikasi view bilan chalkashib ketgan

To'g'ri model:

- `Level` bu semantic anchor
- `View` bu ko'rish usuli

Ammo amalda bir necha marta level behavior sahna/controller bilan aralashib ketgan.

Signal fayllar:

- `apps/viewer_flutter/lib/src/viewer_app.dart`
- `apps/viewer_flutter/lib/src/render_scene_level_overlay.dart`
- `apps/viewer_flutter/lib/src/render_scene_viewport_projection.dart`
- `apps/viewer_flutter/lib/src/render_scene_viewport_planar.dart`

Muammo ko'rinishlari:

- level select ishlashi bilan scene filtering aralashib qoladi
- active level ba'zida semantic selection, ba'zida visible scene policy vazifasini oladi
- elevation editing va wall level constraint bitta coherent flow emas

To'g'ri yakuniy holat:

- level oddiy semantic object
- selectable bo'ladi
- elevation edit qilinadi
- wall base/top constraint bilan unga ulanadi
- plan/elevation/3D bitta modelni boshqa projectionda ko'rsatadi

### 2.3 Wall vertical constraint flow hali to'liq yakunlanmagan

Engine tarafda muhim API bor:

- `move_level_elevation`
- `set_wall_level_constraints`

Manzillar:

- `src/api/include/tbe/api/EngineApi.hpp`
- `src/api/src/EngineApi.cpp`
- `src/core/include/tbe/core/Document.hpp`
- `src/core/src/Document.cpp`

Bu yaxshi.

Lekin product-level workflow hali muammoli:

- level select -> wall select -> base/top level biriktirish UX hali toza emas
- selected wall uchun constraint inspector mavjud, lekin behavior barqaror emas
- openinglar host wall bilan vertical lock bo'lsa ham viewer feedback doim bir xil emas

Yani backend capability bor, lekin interaction architecture hali yarim yo'lda.

### 2.4 Room / floor / ceiling / roof oqimi bir xil modelga tushmagan

Engine tarafda:

- `create_ceiling_system_for_room`
- `create_ceiling_system_from_profile`
- `create_elements_from_profile`
- `normalized_profile_polygon`

bor.

Lekin product behaviorda hali farq seziladi:

- floor ba'zan chiziladi
- ceiling ba'zan umuman ishlamaydi
- roof draw UX to'liq ulanmagan
- non-rectangular shape uchun manual profile va pick-walls oqimi hamma targetga bir xil ulanmagan

Bu muammo aynan shuni ko'rsatadi:

- semantic create API bor
- lekin UI orchestration hali generic emas

### 2.5 RenderScene bridge kuchli, lekin authoring bridge hali to'liq emas

`RenderScene` viewer uchun yaxshi bridge:

- stable object list
- bounds
- mesh
- metadata

Lekin authoring uchun bular yetmaydi.

Nega:

- draw draft validate qilish kerak
- wall picks ordered boundary bo'lishi kerak
- level lock feedback kerak
- selected element semantic relationships kerak

Shuning uchun `RenderScene` ko'rish uchun yaxshi, lekin edit orchestration uchun uning yonida engine command/requery qatlami doim kerak bo'ladi.

### 2.6 Fallback geometry va semantic behavior orasida farq bor

Hozir geometry real CAD solid/boolean emas.

Bu ochiq cheklov:

- `docs/engine_mvp_architecture.md`
- `docs/render_scene.md`
- `docs/core_v0_1_limitations.md`

Oqibat:

- wall join vizual topologiya ba'zan buziladi
- opening cut ba'zan oddiy "mesh correction" kabi ko'rinadi
- viewerda ko'rgan narsa semantic modelga nisbatan 100% CAD-solid bo'lmaydi

Bu normal, lekin product expectation bilan hujjatlashtirilgan reality o'rtasida farq bor.

### 2.7 Projection/view architecture nisbatan toza, lekin product editing bilan hali to'liq birlashmagan

Projection layer ancha toza:

- `apps/viewer_flutter/lib/src/render_scene_viewport_planar.dart`
- `apps/viewer_flutter/lib/src/render_scene_viewport_projection.dart`
- `docs/projection_view_architecture.md`

Bu qatlam kuchli.

Lekin edit tools bilan integratsiya qismida hali muammo bor:

- plan-only edit affordance va general semantic edit oqimi ajralishi kerak
- level line hit-test, object pick, wall drag, opening drag, profile draw hammasi bir policy bilan yurishi kerak

Hozir esa ayrim interactionlar alohida o'sib ketgan.

---

## 3. Nega amalda shu holatga keldik

### 3.1 Juda ko'p milestone ketma-ket build qilingan

Loyiha juda tez ko'p bosqichdan o'tgan:

- walls/rooms
- schedules/takeoff
- materials
- roof/column/beam/stair
- C ABI
- RenderScene
- Next.js reference viewer
- Flutter viewer
- edit preview
- level/elevation

Bu tezlik yaxshi.

Lekin ayrim joylarda:

- vaqtinchalik demo helper keyin olib tashlanmay qolgan
- engine capability qo'shilgan, lekin eski local helper ham qolgan
- UI arxitekturasi to'liq "reset" qilinmasdan ustma-ust o'sgan

### 3.2 Demo pressure arxitektura pressure'dan oldinga chiqib ketgan

Tez ko'rinadigan natija olish uchun ba'zi yo'llar tanlangan:

- local preview state
- render scene normalization
- local auto room surface sync
- interactive patch-level behavior

Bu qisqa muddatda foydali.

Lekin uzoq muddatda:

- central engine pathni xira qiladi
- duplication paydo qiladi

### 3.3 "Viewer ham editor bo'lib ketdi"

Viewer aslida:

- render
- pick
- preview
- inspector

bo'lishi kerak edi.

Lekin amalda u qisman semantic mutatorga ham aylanib qolgan.

Bu eng katta arxitektura signal.

---

## 4. Qaysi narsalar yaxshi holatda

Barchasi yomon emas.
Aksincha, kuchli tayyor qismlar bor:

### 4.1 Core foundation yaxshi

- `Document`
- typed semantic data
- commands / edits
- save/load
- validation
- schedules
- takeoff
- RenderScene export

### 4.2 API boundary yaxshi yo'nalishda

- C++ API
- C ABI
- Flutter FFI bridge

Bu katta yutuq.

### 4.3 Projection registry yaxshi

Plan / elevation / 3D ni bitta matematik modelga birlashtirish yo'nalishi to'g'ri.

### 4.4 Docs va test bazasi bor

Repo ichida allaqachon muhim hujjatlar mavjud:

- `docs/project_overview_uz.md`
- `docs/engine_mvp_architecture.md`
- `docs/projection_view_architecture.md`
- `docs/render_scene.md`
- `docs/engine_robustness.md`

Testlar ham mavjud:

- `tests/core_tests.cpp`
- `tests/api_tests.cpp`
- `apps/viewer_flutter/test/widget_test.dart`

Yani bu loyiha "chalkash prototip" emas.
Lekin markazlashmagan joylarni yig'ib olish kerak.

---

## 5. Hozirgi eng to'g'ri strategik qaror

### 5.1 Bitta qat'iy qaror kerak

Qaror:

`semantic permanent mutation faqat engine orqali`

Bu degani:

- viewer local scene ni authoritative o'zgartirmaydi
- `RenderSceneEditor` local mutation markazi bo'lmaydi
- u faqat preview/math/helper qatlam bo'lib qoladi

### 5.2 Unified drawing kernel ni to'liq tugatish kerak

Har bir draw target:

- wall
- floor
- ceiling
- roof

bitta draft controller + bitta engine profile create path orqali yurishi kerak.

### 5.3 Level systemni semantic object sifatida yakunlash kerak

Level:

- selectable
- editable
- moveable
- wall base/top constraint bilan bog'liq
- opening/floor/ceiling/roof update propagation markazi

bo'lishi kerak.

### 5.4 Viewer local helpersni kamaytirish kerak

Quyidagilar vaqtinchalik/chegaralangan bo'lib qolishi kerak:

- `normalizeSceneGeometry`
- local add wall/door/window
- local auto surface sync

Yakuniy oqim:

- Flutter gesture
- draft state
- engine API command
- fresh recompute
- RenderScene reload

---

## 6. Muammolarni prioritet tartibida yopish

### P0: Source of truth ni bittaga tushirish

Yopilmasa qolgan hammasi qayta-qayta buziladi.

Ishlar:

- `RenderSceneEditor` dan permanent mutationlarni chiqarish
- draw/create flow'larni engine API'ga ulash
- viewer fallback scene helper va preview helper roliga tushirish

### P1: Level + wall constraint oqimini yakunlash

Ishlar:

- level select
- level elevation edit
- wall base level / top level attach
- opening vertical lock
- floor/ceiling level anchoring

### P2: Unified surface drawing

Ishlar:

- rectangle
- polyline
- pick-walls

targetlar:

- floor
- ceiling
- roof

### P3: Non-rectangular demo-grade house workflow

Ishlar:

- L-shape room walls
- manual floor from polyline
- manual ceiling from polyline
- manual roof from same boundary

### P4: Geometry visual quality

Ishlar:

- wall join cleanup
- opening cut consistency
- fallback mesh quality

Bu muhim, lekin semantic arxitekturadan keyin.

---

## 7. Nima qilmaslik kerak

Quyidagilar hozir zararli bo'ladi:

- yana local viewer mutation qo'shib yuborish
- level behaviorni scene slicing bilan aralashtirish
- wall/floor/ceiling/roof uchun alohida-alohida draft engine yozish
- "tez ishlasin" deb engine chetlab o'tish
- fallback geometry limitationini yashirish

---

## 8. Bir gap bilan holat

Loyiha to'xtab qolmagan.

Loyiha `feature build` bosqichidan `architecture consolidation` bosqichiga o'tib qoldi.

Shuning uchun hissiyot shunday bo'lyapti:

- ko'p ish qilingan
- lekin ba'zi zarur narsalar hali "haqiqiy barqaror" ishlamayapti

Sababi:

`markaziy oqim hali to'liq bitta emas`.

---

## 9. Yakuniy qaror

Kelajak uchun qat'iy pozitsiya:

- engine semantic truth
- API authoritative mutation boundary
- RenderScene authoritative render bridge
- Flutter authoritative UI emas, authoritative client
- level semantic object, scene manager emas
- drawing kernel bitta

Shu tozalik tiklanmaguncha, feature qo'shish davom etsa ham oldinga siljish hissi sust bo'ladi.

Shu tozalik tiklansa, keyingi featurelar ancha tez va kam xato bilan qo'shiladi.
