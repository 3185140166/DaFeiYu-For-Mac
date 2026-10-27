# Hoodie hands refinement v2

Tool: built-in image_gen (transparent_background=true), precise-object-edit.
Date: 2026-10-27.
License: these are adaptations of CrossPet artwork, distributed under CC BY-NC-SA 4.0.
Attribution: CrossPet / lokicorvus and CrossPet contributors; character design 上善无形 / ZipZipPipe.
The unedited upstream WebP files remain in the parent directory.

## Idle — final prompt

Use case: precise-object-edit. Edit target: the attached 640x640 transparent desktop-pet sprite. Make an extremely localized edit ONLY to the two hands and sleeve openings. Preserve the exact character identity, blue hair, face, open-eye smiling expression, orange hair clip, whale tail, cream Claude hoodie with name badge text exactly 'Claude', skirt, boots, pose, full-body scale, head position and original silhouette everywhere except the hands. The tiny circular hands currently merge with the cream sleeves at waist level: make each a clearly visible cute chibi HUMAN hand extending out beyond its sleeve, slightly turned outward, with warm peach skin, one readable thumb and 3 simplified finger contours. Hands should be slightly larger for readability at 240px desktop-pet height, about 8% of head width each. Add a thin warm orange trim around each sleeve opening and a clean medium-dark brown outline separating skin from fabric. Keep both arms in the same lowered bent position, only rotate the hands outward a little. No paw pads, no gloves, no added props, no changes to the rest of the art, no background, no shadows outside the character, no watermark. Return one full character on a genuinely transparent square canvas, same framing and alignment as input; keep whole character and tail visible. Match the original soft cel-shaded anime chibi style.

Edit target: original normalized hoodie_stand.png (prepared from ../idle.webp).
Selected output: idle-hands-v2.png.

## Happy — final prompt

Use case: precise-object-edit. Image 1 is the EDIT TARGET, an exuberantly happy blue-haired whale girl with closed smiling eyes, BOTH ARMS RAISED and ONE LEG LIFTED. Image 2 is ONLY a supporting reference for the improved hand design: exposed warm peach chibi human palms, clean warm brown contour, thin orange sleeve-opening trim. Edit image 1 ONLY around both hands and sleeve openings: reveal clearly visible friendly open palms extending out of the raised cuffs, slightly larger for readability at desktop-pet height 240px. Show a readable thumb and 3 simplified finger contours on each hand, same size/style as supporting image 2. Keep both arms raised diagonally exactly as image 1, keep its closed eyes and delighted open mouth, leg raised pose, hair contours, orange flower hair clip, blue whale tail, cream hoodie, orange skirt, boots, pendant and exact name badge text 'Claude'. Do NOT copy the lowered arms, open eyes, standing pose or framing of image 2. Preserve the target's head size, position, full body scale and alignment. No paw pads, no gloves, no new props, no new text, no watermark, no background or external shadow. One full-body character on a genuinely transparent square canvas, entire tail and boots visible. Same original soft cel-shaded chibi illustration style. Change only hands and sleeve edges.

Edit target: original normalized hoodie_face_happy.png (prepared from ../happy.webp).
Supporting reference: idle-hands-v2.png.
Selected output: happy-hands-v2.png.

## Integration

Both selected outputs are 1254×1254 RGBA PNGs. scripts/prepare_hoodie_art.swift
scales them uniformly to matching 640×640 transparent runtime sprites without
cropping. Header, menu icon and application icon are regenerated from the idle pose.
Image generation also redraws some surrounding linework; original upstream files
are preserved for comparison or rollback with `swift scripts/prepare_hoodie_art.swift --original`.
