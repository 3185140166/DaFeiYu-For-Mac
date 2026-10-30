# Continuous layered gait v7 — 2026-10-29

Reference: licensed hoodie_walk_right_0.png derived from CrossPet / lokicorvus and contributors, 上善无形 / ZipZipPipe. All artwork and rendered derivatives retain CC BY-NC-SA 4.0.

Built-in image_gen edits with transparent_background=true. Selected source assets: body.png and boot.png. Original source files are retained unchanged.

Body prompt: preserve full head, hair, tail, face, arms, cream Claude hoodie, orange skirt and complete scalloped white hem; remove both legs and boots below skirt, no thigh stubs; keep muted original palette, full silhouette, badge Claude, transparent background.

Leg prompt: one isolated short chibi leg and cream/apricot boot, flower, toe points right, horizontal sole, no head/body/other limb. Revision: shorten skin stub to 15% of height; remove external glow and haze. The generator still emitted translucent glow; preparation retains the solid silhouette and a one-pixel antialias boundary, then crops the boot cuff by its explicit asset coordinate. No body pixel colors are used to remove limbs.

Native rig: fixed torso covers roots of two rounded, articulated native thigh paths, each attached to its own hip. Both legs use the same boot texture. Each foot has 60% planted stance, moving backward at the pace of desktop motion; 40% swing, easing forward with a lifted passing phase. Legs offset by half a cycle, with persistent near/far depth order. Contact, passing and cycle wrap are continuous. 24 offline-rendered poses/direction, 896x640. Badges re-typeset after mirroring. Runtime plays exported frames; no per-frame limb extraction, color swapping or compositing discontinuity.

Rebuild: bash scripts/prepare_hoodie_motion.sh. Body stays identical across all rendered frames; tests inspect rendered alpha differences including wrap, skin/hem continuity, source margins and persistent foot trajectory.
