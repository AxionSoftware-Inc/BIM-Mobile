# v0.1 Ishlash va Release Qoidalari

## Majburiy tekshiruv

Har bir wall/opening o'zgarishida `bash tools/run_wall_opening_smoke.sh` ishlaydi.
Ssenariy ikki devor yaratadi, bittasiga eshik va oyna orqali haqiqiy bo'shliq
ochadi, oynani bitta atomik command bilan o'zgartiradi, undo/redo qiladi va
ikkinchi devorning mesh'i o'zgarmaganini tekshiradi. Shu test CI ichida ham
alohida ko'rinadi.

Debug buildda **Diagnostics** tugmasi quyidagilarni ko'rsatadi:

- ko'k — native wall axis va uning endpointlari;
- binafsha — engine bergan silhouette;
- havorang — engine bergan window/door opening contour;
- har obyektning stable ID'i.

Bu overlay geometriya yaratmaydi. U faqat engine `RenderScene` ma'lumotini
proyeksiya qiladi; demak muammoni `core`, API/cache yoki viewport qatlamiga
aniq ajratish mumkin.

## Koordinata qoidasi

v0.1 faqat `meters` va `X/Y plan, Z up` kontraktini qabul qiladi. RenderScene
versiyalari 1–2 o'qiladi, ammo yangi engine v2 chiqaradi. Noma'lum birlik,
o'qlar yoki kelajak versiyasidagi sahna viewportga yuklanishidan oldin rad
qilinadi — yashirin millimetr/metr yoki axis xatosi modelga tarqalmaydi.

## Branch va release siyosati

| Tur | Qoida |
| --- | --- |
| `main` | Faqat CI yashil bo'lgan, releasable kod. GitHub branch protection: PR, kamida bitta review va `Quality gates` majburiy. |
| `feature/<qisqa-nom>` | Bitta vazifa uchun. PR merge bo'lgach remote branch archive/delete qilinadi. |
| `freeze-*` | Endi faol rivojlanish branchi emas. Tarixiy snapshot sifatida annotated tag/release bilan almashtiriladi. |
| `v0.1.0` | v0.1 commitidan annotated tag va GitHub release. Flutter ilovasi versiyasi mustaqil qoladi. |

2026-09-01 holatida quyidagi remote branchlarning barchasi `origin/main`ga
merge bo'lgan va tegishli immutable tag bilan saqlangan:

- `origin/codex/freeze-main-2026-08-28` → `freeze-viewport-stable-2026-08-28`
- `origin/codex/freeze-main-openings-2026-08-28` → `freeze-viewport-openings-2026-08-28`
- `origin/codex/freeze-main-brick-joints-2026-08-28` → `freeze-viewport-brick-joints-2026-08-28`
- `origin/codex/freeze-main-brick-opening-gaps-2026-08-28` → `freeze-viewport-brick-opening-gaps-2026-08-28`
- `origin/codex/freeze-main-wall-voids-2026-08-28` → `freeze-viewport-wall-voids-2026-08-28`
- `origin/codex/freeze-main-white-walls-2026-08-28` → `freeze-viewport-white-walls-2026-08-28`

Ular yangi ish uchun ishlatilmaydi va remote'dan o'chirishga tayyor
kandidatdir. Retention muddati jamoa tomonidan tasdiqlangandan keyingina
o'chiriladi; bu qasddan qaytarib bo'lmaydigan amaliyotni avtomatlashtirmaydi.

## Qurilmadagi smoke checklist

Android debug buildda:

1. Bo'sh projectda 8 m devor va unga oyna yarating.
2. Diagnostics bilan cyan opening contour devordagi haqiqiy kesimga mosligini tekshiring.
3. Oynani chap/o'ngga suring, kengligini o'zgartiring, Undo va Redo qiling.
4. Ikkinchi devorni tanlab uning mesh'i yoki ID'i o'zgarmaganini tekshiring.
5. Plan, elevation va 3D'da natija bir xil modeldan chiqishini tekshiring.

Qurilmadagi avtomatlashtirilgan variant:
`flutter test integration_test/tablet_wall_opening_workflow_test.dart -d <android-device-id>`.
