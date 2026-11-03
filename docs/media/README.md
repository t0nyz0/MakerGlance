# Native demo media

All screenshots in this directory are captured from the production SwiftUI/AppKit views using `--demo`. Every profile, model, follower and activity value is fictional. No live library, account balance, private inbox, credential or external image is used.

The original model illustrations are drawn locally by `DemoArtwork.swift`. The app icon is rendered from `scripts/Icon.swift`. These are project artwork, not photographs borrowed from MakerWorld creators.

```sh
bash scripts/capture-demo.sh
swift scripts/Icon.swift docs/media/icon.png
python3 scripts/check_documentation.py --strip-png-metadata
python3 scripts/build_demo_animations.py --verify docs/media
```

The capture uses a temporary isolated library and an owned native window. It does not accept system permissions or inspect other applications. Public media is copied into this directory only after a successful capture. The native views carry an explicit DEMO label; menu captures have a corresponding fictional-activity label. `PROVENANCE.txt` records the capture source.

`dashboard-full-dark.png` and its light counterpart contain the whole native Dashboard from its top through the last history row. The documentation-only window can exceed the physical display height. The detail scroll content must fit before capture succeeds; `CAPTURE-CHECKS.json` records its measured height and workflow checks. The image is not stitched, cropped or reconstructed.

Three seven-second GIFs demonstrate native Cards/Compact actions, a fictional one-print increase followed by an unchanged successful check, and native 24-hour/seven-day history controls. The print sequence uses `ModelCheckRecency`; it does not simulate live server polling. Focused GIFs render the same production watched-model section, model card and history mosaic at readable native component sizes; they receive a separate explicit fictional-demo caption. Explanatory print captions sit outside the native card. The complete Dashboard overview is uncropped. GIF timing, frame counts and sizes are recorded in `ANIMATIONS.json`.

The encoder uses Pillow from the documentation [requirements](../presentation/requirements.txt). It produces a shared 256-color palette and optimized frame updates. Static posters provide reduced-motion alternatives and linked fallbacks in the README. Raw animation frames remain temporary and are excluded from the repository.

Review every image for personal data before staging. Raw live-account audits belong outside the repository. Text/EXIF chunks are removed without changing pixels or color profiles, and checked before staging. The README and deck use only these approved files.

The My Prints dark/light views use original fictional cloud-job fixtures and local artwork. They include sample printer/plate names, explicit statuses and sample dates. No real print-job name, device ID, thumbnail URL or image is included. The new presentation slide uses a focused crop of this same native view.
