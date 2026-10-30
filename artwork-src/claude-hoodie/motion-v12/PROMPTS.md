# Hands-in-pocket walking torso v12 — 2026-10-30

Built-in image_gen edit with transparent_background=true of v7/body.png. Selected source: pocket-body.png. Source art and derivative retain CC BY-NC-SA 4.0, attribution CrossPet / lokicorvus and contributors, 上善无形 / ZipZipPipe.

Prompt: change only both arms/hands into relaxed hands inserted into the hoodie's front kangaroo pocket. Both forearms angle inward/downward, orange cuffs enter the pocket openings, hands completely concealed; elbows subtly outward without flaring. Preserve the same head, face, blue hair, tail, flower, Claude badge, complete skirt and scalloped hem, muted palette and legless transparent framing. No legs/boots added.

Integration: use one fixed pocket torso for all 24 poses per direction. Remove previous arm deformation field and its motion function. Existing native short round legs, low shoes, skirt-derived hip center, continuous step trajectory and mild runtime body bob retained. The regular front idle and happy expression remain their existing images. Pose transitions continue to crossfade when walking starts/stops. Tests require pixel-identical torso throughout the cycle plus existing direction, connection, margin and foot continuity checks. Regenerate via bash scripts/prepare_hoodie_motion.sh.
