# Color consistency v6 — 2026-10-28

Built-in image_gen edits of v5 opposite-half-sheet.png, with v4 walk-right-alternating.png as palette reference. Transparent output. All source art and derivatives retain CC BY-NC-SA 4.0 and the CrossPet / lokicorvus, contributors, 上善无形 / ZipZipPipe attribution.

Prompts: change colors only, preserve 2x2 arrangement and all four complete opposite-footfall poses; match muted dusty blue hair, cream fabric and soft apricot orange. First result was too gray; second was still saturated; final asks for a small decrease in blue/orange saturation and a shift from coral toward apricot. Selected: opposite-half-colors-final.png. Other trials retained for provenance, not used by the application.

The preparation script prefers this corrected source while keeping v5 original. Because generation cannot guarantee exact palette matching, PetWalkPalette applies deterministic hue/saturation matching at decode time against the first walk pose. It operates on blue and orange hue families, uses soft membership boundaries, preserves HSV value and every alpha pixel, and caches the result. There is no per-display-frame processing and no geometry or limb cutting. Tests and GIF export use the same decoded images as the app.
