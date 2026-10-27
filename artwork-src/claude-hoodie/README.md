# Claude 卫衣大肥鱼素材出处

Artwork: CrossPet / lokicorvus and CrossPet contributors.
DeepSeek character design: 上善无形（原型「溟月」） / ZipZipPipe（女仆鲸鱼娘）。
Source repository: https://github.com/lokicorvus/crosspet
Source revision: 6e98970f6ff9b44e8ac85215241cabcd78f67d92
Source files:
- characters/deepseek-hoodie/idle.webp
  SHA-256: f81ba87fc581f1215ae762451b60defb76a72c433068ac8cd46b6857ce7fd97f
- characters/deepseek-hoodie/happy.webp
  SHA-256: 28dec659369c4e91f6dcb1f0b95df31b146a65d281f4d46933bec3db4132f9ae

License: CC BY-NC-SA 4.0
https://creativecommons.org/licenses/by-nc-sa/4.0/
Upstream notice: CROSSPET_LICENSE.md in this directory.

Adaptations in this project: converted WebP to PNG and centered both poses on a common
640×640 transparent canvas without resizing the source artwork; derived a head icon,
a settings header, a gradient-backed application icon and runtime rotated head crops.
These source images and derivatives are CC BY-NC-SA 4.0, not covered by the code's MIT license.
Attribution, noncommercial use and ShareAlike apply. No endorsement by Anthropic or DeepSeek.

Derived files: Sources/Resources/hoodie_stand.png, hoodie_face_happy.png,
MenuBarIcon.png, header.png, AppIcon.icns; icon-src/AppIcon_1024.png.
Reproduce: swift scripts/prepare_hoodie_art.swift; swift scripts/gen_menubar_icon.swift;
swift scripts/gen_icon.swift; bash scripts/update_icon_bundle.sh.
