# Online IFC starter projects

The start screen includes three lightweight IFC sample cards and one larger
multi-storey office model:

- Building Architecture — 226 KB
- Building Structural — 297 KB
- Infrastructure Road — 439 KB
- KIT Office Building — 10.9 MB

They come from the public buildingSMART Certification Datasets repository.
The app downloads a selected file only when its card is opened, stores it in
the app project cache, and reuses that cached file on later opens. No IFC
payload is bundled into the APK and the preview is drawn with Flutter canvas
 primitives, so the launch screen does not decode a large model or image.

Source: <https://github.com/buildingSMART/Certification-datasets>

The KIT model is listed in the [KIT IFC examples](https://www.ifcwiki.org/index.php?title=KIT_IFC_Examples)
catalogue. It is downloaded on demand and cached in the app project storage;
it is not bundled into the APK.

The samples are demonstrative/certification data. Before redistributing any
downloaded sample outside the app, check the repository's current terms and
retain the source attribution.
