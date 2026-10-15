# OrbitConvert — Third-party notices / 第三方许可与致谢

## UnRAR 7.3.1 · source-available extraction license

Copyright Alexander Roshal. Official source:
https://www.rarlab.com/rar/unrarsrc-7.3.1.tar.gz

OrbitConvert bundles the UnRAR extraction engine and uses it solely to read and
decrypt RAR archives. No RAR compression functionality is included. The original
engine source is in Vendor/UnRAR/unrar; integration code is OrbitUnRAR.cpp.
See UNRAR_LICENSE.txt for the complete license; this component is not MIT/BSD.

UnRAR source code may be used in any software to handle RAR archives without
limitations free of charge, but cannot be used to develop RAR (WinRAR)
compatible archiver and to re-create RAR compression algorithm, which is
proprietary. Distribution of modified UnRAR source code in separate form or
as a part of other software is permitted, provided that full text of this
paragraph, starting from "UnRAR source code" words, is included in license,
or in documentation if license is not available, and in source code comments
of resulting package.

## libFLAC 1.5.0 / libogg 1.3.5 · BSD

FLAC encoding uses libFLAC (https://xiph.org/flac/), linked to libogg
(https://xiph.org/ogg/). Only the BSD-licensed libraries are included, not their
GPL command-line tools. Copyright Xiph.Org Foundation and contributors.
See FLAC_LICENSE.txt and OGG_LICENSE.txt for the complete notices.

## LAME 3.100 · LGPL v2 or later

MP3 encoding uses the separate dynamically loaded libmp3lame library.
Copyright belongs to the LAME authors. Project: https://lame.sourceforge.io/.
See LAME_LICENSE.txt. Corresponding unmodified source and build instructions
are bundled in Resources/LAME-Source. Only the encoder is built; the frontend
and decoder are disabled. Debugging modifications to this library is permitted.
No user installation of LAME or another application is required.

This file describes third-party components, not the license of OrbitConvert's
own code or its brand. Original copyright and license notices must be retained.
许可文本可从设置中的“开源许可”离线查看。

No LibreOffice or OfficeEngine.app is bundled, downloaded, or required.

Included:
- libwebp 1.6.0 and libsharpyuv from the local development runtime.
  BSD license: WEBP_LICENSE.txt. Source: https://github.com/webmproject/libwebp
  Additional patent grant: WEBP_PATENTS.txt.
  SPDX license identifier: BSD-3-Clause. Reviewed upstream tag: v1.6.0.
- Native PresentationConverter, SpreadsheetConverter and Office XML helpers adapted
  from FileFlipper, MIT, copyright (c) 2026 FileFlipper contributors.
  https://github.com/Aimee51819/FileFlipper
  Source revision: 1a03b2c96ed011881493db9882a8df2959d42fb9
  Full license: FILEFLIPPER_LICENSE.txt (also included in the app bundle).
  SPDX license identifier: MIT.
  OrbitConvert modifications: private outputs; removed Markdown routes; bounded
  archives/XML/pages/cells/images; resource checks; external relationships disabled.
  The upstream ZIP reader is NOT used; OrbitConvert uses system libarchive.

AppKit, CoreGraphics, ImageIO, Vision, PDFKit and /usr/lib/libarchive.2.dylib
are provided by macOS, not copied into this app. libarchive is loaded in-process
with runtime symbol checks; no tar/unrar/zip/unzip subprocess is used.
https://www.libarchive.org/

Pages, Numbers and Keynote are NOT bundled. Only Apple-native .pages/.numbers/.key
exports may call those installed apps, after the user enables the setting.
DOCX/PPTX/XLSX do not use those apps, even when that setting is enabled.

RAR regression fixtures used in work/native-tests are from libarchive v3.7.4,
https://github.com/libarchive/libarchive/tree/v3.7.4/libarchive/test
They are test data only and are not shipped in the app.

This is a locally ad-hoc signed Apple Silicon build, not a notarized release.
Licensing does not imply endorsement by Google, FileFlipper, Apple or any other
upstream contributor. Changes to dependencies require a new license review.
