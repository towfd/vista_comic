Type: grilling
Status: resolved

# OCR and translation stay backend-side; iOS is not touched

## Question

The two capabilities the reading-to-vocabulary flow depends on are both on-device on iOS: `VisionOCRRecognizer.swift` wraps Vision, and `AppleTranslator.swift` wraps Apple's Translation framework. A browser has neither. Where do OCR and translation live for the web — moved to the backend and shared by both clients, duplicated backend-side for the web only, or done inside the browser?

## Answer

**A second implementation, backend-side, for the web only. The iOS app is not modified.**

Moving both to the backend and switching iOS over was the tidier option and was rejected on what it would cost: iOS would lose offline OCR, which works today with no connection at all, and it would mean changing an already-shipped, device-verified path for a feature iOS does not need. Doing OCR inside the browser (WASM) was rejected on recognition quality — the library is Vietnamese-subtitled scanlations, and the diacritics are exactly what a lightweight in-browser engine loses.

**The accepted cost, recorded so it is not later mistaken for a defect**: the same line can produce different recognized text and different wording on the phone and on the computer. Two engines, two results. The developer was told this and confirmed it.

This decision is narrower than it looks — see [No translation engine on the web](07-no-translation-engine-on-the-web.md), which removes the translation half entirely, so the only genuinely new backend capability is OCR.

## Comments

Resolved via the `/grilling` session on 2026-09-16 that created this map.
