# Visible legs and low shoes v8 — 2026-10-29

Built-in image_gen edit of licensed v7 boot.png. Prompt: replace tall shaft and skin with one low-cut chibi cream/apricot sneaker, flower at heel, right-pointing toe, flat white-striped sole, height less than half width; no leg, shaft, glow or background. Selected source: shoe.png. CC BY-NC-SA 4.0 and CrossPet / lokicorvus, contributors, 上善无形 / ZipZipPipe attribution retained.

The fixed torso remains v7/body.png. No image pixels of the torso are removed. The native rig now anchors hips behind the actual hem at y516, joins hips to a bending knee and ankle with a continuous tapered outline, and overlaps ankles inside the low shoe collar. Source shoe bounds are retained whole. At normal size shoes are approximately 25–27 source pixels tall instead of 73–78; exposed leg length is correspondingly greater. Tests flood-fill rendered lower-body alpha from skirt to both shoes and check exposed skin in every frame/direction.

## v9 proportion refinement (2026-10-29)

Native geometry only: compare against the happy/idle chibi reference. Raise sole baseline from y620 to y604; widen thighs from 32 to 48 and calves from 28 to 42 source pixels; ankle width from 21 to 35. Retain low shoes, slightly increase their thickness and width. Add subtle native shaded fill inside the unchanged connected leg paths. Foot half-range 32.256, lift18; default speed33.6pt/s and stride40.32pt preserve the1.2s cycle and matching planted-foot speed. No new bitmap generation; same torso/shoe source and license.

## v10 pelvis alignment (2026-10-29)

The torso is three-quarter-facing: face center is forward of the skirt. Determine the fixed pelvis from the median midpoint of the skirt's orange band across y485–515 in the normalized body. The measured x375.39 replaces old x417, moving both fixed hips ~41.6 pixels backward in the canonical right-facing art; the whole rendered pose is mirrored for left. Each leg still moves relative to its own fixed hip. Source pixels, proportions and trajectory timing unchanged.

## v11 counter-swing arms (2026-10-29)

Native animation only, no regenerated body art. Cache one normalized torso and inverse-map two smooth shoulder-anchored deformation fields over its sleeve/hand areas. Wrist offset is -0.42 times the same-side foot's horizontal offset. Shoulders and all pixels above y370 remain fixed; tiny upward wrist arc and smooth lower-region fade keep the sleeve/palm attached. Bilinear premultiplied-alpha sampling preserves the existing illustration palette. All 24 arm poses are prepared offline with the same gait phase as the legs. Rendered hand centroids are tested against opposite footfalls, together with the existing head stability and limb-connection checks.
