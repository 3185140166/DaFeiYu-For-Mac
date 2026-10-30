# Idle-style rounded footwear v13 — 2026-10-30

Built-in image_gen edit using the actual hoodie_face_happy.png as reference. Transparent background. Selected asset: puffy-shoe.png. Attribution CrossPet / lokicorvus and contributors, 上善无形 / ZipZipPipe; source and derivatives remain CC BY-NC-SA 4.0.

Prompt: isolate one compact chibi orange Mary-Jane-like rounded shoe with soft scalloped cream ankle cuff and small orange flower, matching the static reference's illustrated footwear. Warm muted cream/apricot palette, soft cel shading and brown outline; no straight tall shaft, sports laces, bare leg, glow or background. Right-facing three-quarter view, cuff upper45%, shoe lower55%, height about80% width, complete isolated transparent silhouette.

Integration: same fixed pocket torso and persistent continuous native legs. Use natural footwear aspect ratio at 68/72 source-pixel widths; align the leg into the cuff at x36% of footwear width, y16% of height, overlapping behind the opaque cuff. Sole baseline y620 allows short rounded exposed thighs above the soft cuff. No independently regenerated per-frame art or palette shifts. Existing 24-frame/direction stride, skirt-derived hip center, hit testing and idle/happy illustrations retained. Rebuild via bash scripts/prepare_hoodie_motion.sh; test via bash Tests/run_skin_tests.sh.

## v14 ankle/cuff layering (2026-10-30)

Native composition refinement with the same untouched shoe source. Footwear height is 78% of its natural-aspect rendition. Render rear cuff/shoe first, then the continuous thigh/calf/ankle, then the front rim/sides using an open oval ankle aperture. The ankle overlaps inside to 30% shoe height; a narrow 24px opening with a rounded front lip preserves the flower and cuff sides. This exposes the shin in front of the rear cuff without painting the entire shoe over the leg. Existing leg attachment, continuity and gait checks cover all 48 poses.

## v15 compact leg proportions (2026-10-30)

Native geometry only. Raise sole baseline from620 to604 and narrow hip spacing36 to32 source pixels, keeping the skirt-based pelvis. Place knees halfway between hip and ankle with a small flexion offset rather than a fixed knee baseline; preserve rounded widths and soft skin shading. Same unmodified footwear texture and rear-cuff/leg/front-rim ordering. Foot range reduced32.256 to27.648 and lift18 to15. Default speed28.8pt/s and stride34.56pt retain the1.2s alternating cycle, matching shorter legs without rapid steps. Existing all-pose connected-limb, visibility and cycle checks pass.
