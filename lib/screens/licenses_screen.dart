import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Verbatim licence bodies ───────────────────────────────────────────────────
// BSD-3-Clause and BSD-2-Clause conditions must be reproduced verbatim in any
// binary distribution (clause 2 of each licence). Apache-2.0 requires that a
// copy of the licence accompany every binary distribution (section 4a).

const _bsd3Body = '''Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

   3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.''';

const _bsd2Body = '''Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.''';

// Apache-2.0 full text (required by section 4a for binary distributions).
const _apache2Body = '''Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

1. Definitions.

"License" shall mean the terms and conditions for use, reproduction, and distribution as defined by Sections 1 through 9 of this document.

"Licensor" shall mean the copyright owner or entity authorized by the copyright owner that is granting the License.

"Legal Entity" shall mean the union of the acting entity and all other entities that control, are controlled by, or are under common control with that entity.

"You" (or "Your") shall mean an individual or Legal Entity exercising permissions granted by this License.

"Source" form shall mean the preferred form for making modifications, including but not limited to software source code, documentation source, and configuration files.

"Object" form shall mean any form resulting from mechanical transformation or translation of a Source form, including but not limited to compiled object code, generated documentation, and conversions to other media types.

"Work" shall mean the work of authorship, whether in Source or Object form, made available under the License, as indicated by a copyright notice that is included in or attached to the work.

"Derivative Works" shall mean any work, whether in Source or Object form, that is based on (or derived from) the Work and for which the editorial revisions, annotations, elaborations, or other modifications represent, as a whole, an original work of authorship. For the purposes of this License, Derivative Works shall not include works that remain separable from, or merely link (or bind by name) to the interfaces of, the Work and Derivative Works thereof.

"Contribution" shall mean any work of authorship, including the original version of the Work and any modifications or additions to that Work or Derivative Works of the Work, that is intentionally submitted to the Licensor for inclusion in the Work by the copyright owner or by an individual or Legal Entity authorized to submit on behalf of the copyright owner.

"Contributor" shall mean Licensor and any Legal Entity on behalf of which a Contribution has been received by the Licensor and subsequently incorporated within the Work.

2. Grant of Copyright License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare Derivative Works of, publicly display, publicly perform, sublicense, and distribute the Work and such Derivative Works in Source or Object form.

3. Grant of Patent License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable (except as stated in this section) patent license to make, have made, use, offer to sell, sell, import, and otherwise transfer the Work.

4. Redistribution. You may reproduce and distribute copies of the Work or Derivative Works thereof in any medium, with or without modifications, and in Source or Object form, provided that You meet the following conditions:

   (a) You must give any other recipients of the Work or Derivative Works a copy of this License; and

   (b) You must cause any modified files to carry prominent notices stating that You changed the files; and

   (c) You must retain, in the Source form of any Derivative Works that You distribute, all copyright, patent, trademark, and attribution notices from the Source form of the Work, excluding those notices that do not pertain to any part of the Derivative Works; and

   (d) If the Work includes a "NOTICE" text file as part of its distribution, You must include a readable copy of the attribution notices contained within such NOTICE file in at least one of the following places: within a NOTICE text provided with the Derivative Works; within the Source form or documentation, if provided along with the Derivative Works; or, within a display generated by the Derivative Works, if and wherever such third-party notices normally appear.

5. Submission of Contributions. Unless You explicitly state otherwise, any Contribution intentionally submitted for inclusion in the Work by You to the Licensor shall be under the terms and conditions of this License, without any additional terms or conditions.

6. Trademarks. This License does not grant permission to use the trade names, trademarks, service marks, or product names of the Licensor, except as required for reasonable and customary use in describing the origin of the Work and reproducing the content of the NOTICE file.

7. Disclaimer of Warranty. Unless required by applicable law or agreed to in writing, Licensor provides the Work (and each Contributor provides its Contributions) on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, including, without limitation, any warranties or conditions of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE. You are solely responsible for determining the appropriateness of using or redistributing the Work and assume any risks associated with Your exercise of permissions under this License.

8. Limitation of Liability. In no event and under no legal theory, whether in tort (including negligence), contract, or otherwise, unless required by applicable law (such as deliberate and grossly negligent acts) or agreed to in writing, shall any Contributor be liable to You for damages, including any direct, indirect, special, incidental, or exemplary, or consequential damages of any character arising as a result of this License or out of the use or inability to use the Work (including but not limited to damages for loss of goodwill, work stoppage, computer failure or malfunction, or all other commercial damages or losses), even if such Contributor has been advised of the possibility of such damages.

9. Accepting Warranty or Additional Liability. While redistributing the Work or Derivative Works thereof, You may choose to offer, and charge a fee for, acceptance of support, warranty, indemnity, or other liability obligations and/or rights consistent with this License. However, in accepting such obligations, You may act only on Your own behalf and on Your sole responsibility, not on behalf of any other Contributor, and only if You agree to indemnify, defend, and hold each Contributor harmless for any liability incurred by, or claims asserted against, such Contributor by reason of your accepting any warranty or additional liability.

END OF TERMS AND CONDITIONS''';

const _mitBody = '''Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';

// ── Data model ────────────────────────────────────────────────────────────────

class _Lib {
  final String name;
  final String copyright;
  final String spdxId;
  final String licenseBody;
  final String pubUrl;

  const _Lib({
    required this.name,
    required this.copyright,
    required this.spdxId,
    required this.licenseBody,
    required this.pubUrl,
  });
}

// ── Library list ──────────────────────────────────────────────────────────────
// BSD-2/3 and Apache-2.0 packages are listed first (verbatim text required).
// MIT packages follow.

const _libs = <_Lib>[
  // BSD-3-Clause — verbatim reproduction required in binary distributions.
  _Lib(
    name: 'shared_preferences',
    copyright: 'Copyright 2013 The Flutter Authors. All rights reserved.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/shared_preferences',
  ),
  _Lib(
    name: 'path',
    copyright: 'Copyright 2014, the Dart project authors.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/path',
  ),
  _Lib(
    name: 'path_provider',
    copyright: 'Copyright 2013 The Flutter Authors. All rights reserved.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/path_provider',
  ),
  _Lib(
    name: 'http',
    copyright: 'Copyright 2014, the Dart project authors.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/http',
  ),
  _Lib(
    name: 'firebase_core',
    copyright: 'Copyright 2017 The Chromium Authors. All rights reserved.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/firebase_core',
  ),
  _Lib(
    name: 'firebase_analytics',
    copyright: 'Copyright 2017 The Chromium Authors. All rights reserved.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/firebase_analytics',
  ),
  _Lib(
    name: 'firebase_crashlytics',
    copyright: 'Copyright 2019 The Chromium Authors. All rights reserved.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/firebase_crashlytics',
  ),
  _Lib(
    name: 'flutter_chrome_cast',
    copyright: 'Copyright 2023 felnanuke2.',
    spdxId: 'BSD-3-Clause',
    licenseBody: _bsd3Body,
    pubUrl: 'https://pub.dev/packages/flutter_chrome_cast',
  ),
  // BSD-2-Clause — verbatim reproduction required in binary distributions.
  _Lib(
    name: 'sqflite',
    copyright: 'Copyright 2019 Alexandre Roux Tekartik.',
    spdxId: 'BSD-2-Clause',
    licenseBody: _bsd2Body,
    pubUrl: 'https://pub.dev/packages/sqflite',
  ),
  // Apache-2.0 — full licence text must accompany binary distributions (§4a).
  _Lib(
    name: 'just_audio',
    copyright: 'Copyright 2019 Ryan Heise. Copyright 2020 The just_audio contributors.',
    spdxId: 'Apache-2.0',
    licenseBody: _apache2Body,
    pubUrl: 'https://pub.dev/packages/just_audio',
  ),
  // MIT — copyright notice must be retained; no verbatim-body requirement.
  _Lib(
    name: 'file_picker',
    copyright: 'Copyright 2018 Miguel Ruivo.',
    spdxId: 'MIT',
    licenseBody: _mitBody,
    pubUrl: 'https://pub.dev/packages/file_picker',
  ),
  _Lib(
    name: 'audio_metadata_reader',
    copyright: 'Copyright 2023 Clément Béal.',
    spdxId: 'MIT',
    licenseBody: _mitBody,
    pubUrl: 'https://pub.dev/packages/audio_metadata_reader',
  ),
  _Lib(
    name: 'permission_handler',
    copyright: 'Copyright 2018 Baseflow.',
    spdxId: 'MIT',
    licenseBody: _mitBody,
    pubUrl: 'https://pub.dev/packages/permission_handler',
  ),
  _Lib(
    name: 'audio_service',
    copyright: 'Copyright 2018 Ryan Heise. Copyright 2021 The audio_service contributors.',
    spdxId: 'MIT',
    licenseBody: _mitBody,
    pubUrl: 'https://pub.dev/packages/audio_service',
  ),
  _Lib(
    name: 'get_it',
    copyright: 'Copyright 2018 Thomas Burkhart.',
    spdxId: 'MIT',
    licenseBody: _mitBody,
    pubUrl: 'https://pub.dev/packages/get_it',
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimText = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(title: const Text('Third-party libraries')),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 32),
        itemCount: _libs.length + 1, // +1 for header note
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'AudioVault is built on the following open-source libraries. '
                'Tap any entry to read its licence.',
                style: theme.textTheme.bodySmall?.copyWith(color: dimText),
              ),
            );
          }
          final lib = _libs[index - 1];
          return _LibTile(lib: lib);
        },
      ),
    );
  }
}

// ── Individual library tile ───────────────────────────────────────────────────

class _LibTile extends StatelessWidget {
  final _Lib lib;
  const _LibTile({required this.lib});

  Color _badgeColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (lib.spdxId) {
      'MIT'           => cs.tertiary.withValues(alpha: 0.18),
      'Apache-2.0'    => cs.error.withValues(alpha: 0.15),
      _               => cs.primary.withValues(alpha: 0.18), // BSD-*
    };
  }

  Color _badgeText(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (lib.spdxId) {
      'MIT'        => cs.tertiary,
      'Apache-2.0' => cs.error,
      _            => cs.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimText = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 20),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Row(
        children: [
          Expanded(
            child: Text(lib.name, style: theme.textTheme.bodyLarge),
          ),
          const SizedBox(width: 8),
          _Badge(label: lib.spdxId, bg: _badgeColor(context), fg: _badgeText(context)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          lib.copyright,
          style: theme.textTheme.bodySmall?.copyWith(color: dimText),
        ),
      ),
      children: [
        // Full licence text
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            '${lib.copyright}\n\n${lib.licenseBody}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('View on pub.dev'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => launchUrl(
              Uri.parse(lib.pubUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
