import 'dart:convert';
import 'package:http/http.dart' as http;

/// Fetches the latest release from the Kōwhai GitHub repo.
class GithubReleaseService {
  static const _owner = 'mattsteednz';
  static const _repo = 'kowhai';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  static const releasesPageUrl =
      'https://github.com/$_owner/$_repo/releases/latest';

  /// Returns the latest release tag (e.g. `1.7.0`) or `null` on failure.
  Future<GithubRelease?> fetchLatest() async {
    try {
      final response = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
      final url = json['html_url'] as String?;
      if (tag == null || url == null) return null;

      return GithubRelease(version: tag, url: url);
    } catch (_) {
      return null;
    }
  }
}

class GithubRelease {
  final String version;
  final String url;

  const GithubRelease({required this.version, required this.url});
}
