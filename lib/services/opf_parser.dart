import 'package:xml/xml.dart';

/// Metadata extracted from a Calibre/OPF `metadata.opf` file.
class OpfMetadata {
  final String? title;
  final String? author;
  final String? narrator;
  final String? description;
  final String? publisher;
  final String? language;
  final String? releaseDate;
  final String? series;
  final int? seriesIndex;

  const OpfMetadata({
    this.title,
    this.author,
    this.narrator,
    this.description,
    this.publisher,
    this.language,
    this.releaseDate,
    this.series,
    this.seriesIndex,
  });

  bool get isEmpty =>
      title == null &&
      author == null &&
      narrator == null &&
      description == null &&
      publisher == null &&
      language == null &&
      releaseDate == null &&
      series == null &&
      seriesIndex == null;
}

/// Parses a `metadata.opf` XML string and returns an [OpfMetadata] value
/// object. Returns an empty [OpfMetadata] on any parse error — never throws.
///
/// Supported fields:
/// - `dc:title`
/// - `dc:creator opf:role="aut"` → author
/// - `dc:creator opf:role="nrt"` → narrator
/// - `dc:description`
/// - `dc:publisher`
/// - `dc:language`
/// - `dc:date` → releaseDate (year extracted)
/// - Calibre `<meta name="calibre:series" content="..."/>` → series
/// - Calibre `<meta name="calibre:series_index" content="..."/>` → seriesIndex
OpfMetadata parseOpf(String xmlContent) {
  try {
    final doc = XmlDocument.parse(xmlContent);

    // Locate the <metadata> element — may be a direct child of <package> or
    // the root itself in some stripped OPF files. Matched by local name so
    // documents using a default namespace (no `dc:`/`opf:` prefixes) parse.
    final metadata = _allByLocalName(doc, 'metadata').firstOrNull ??
        _allByLocalName(doc, 'dc-metadata').firstOrNull;
    if (metadata == null) return const OpfMetadata();

    String? title;
    String? author;
    String? narrator;
    String? description;
    String? publisher;
    String? language;
    String? releaseDate;
    String? series;
    int? seriesIndex;

    // dc:title
    title = _dcText(metadata, 'title');

    // dc:creator — may appear multiple times with different roles
    for (final el in _byLocalName(metadata, 'creator')) {
      final role = el.getAttribute('opf:role') ??
          el.getAttribute('role') ??
          'aut'; // default role is author when unspecified
      final text = el.innerText.trim();
      if (text.isEmpty) continue;
      if (role == 'aut' && author == null) {
        author = text;
      } else if (role == 'nrt' && narrator == null) {
        narrator = text;
      }
    }

    description = _dcText(metadata, 'description');
    publisher = _dcText(metadata, 'publisher');
    language = _dcText(metadata, 'language');

    // dc:date — extract the year
    final dateText = _dcText(metadata, 'date');
    if (dateText != null && dateText.length >= 4) {
      final year = dateText.substring(0, 4);
      if (int.tryParse(year) != null) releaseDate = year;
    }

    // Calibre custom meta tags
    for (final el in _byLocalName(metadata, 'meta')) {
      final name = el.getAttribute('name') ?? '';
      final content = el.getAttribute('content') ?? '';
      if (content.isEmpty) continue;
      if (name == 'calibre:series') {
        series = content;
      } else if (name == 'calibre:series_index') {
        // Series index may be a float (e.g. "1.0") — round to int
        final d = double.tryParse(content);
        if (d != null) seriesIndex = d.round();
      }
    }

    return OpfMetadata(
      title: title,
      author: author,
      narrator: narrator,
      description: description,
      publisher: publisher,
      language: language,
      releaseDate: releaseDate,
      series: series,
      seriesIndex: seriesIndex,
    );
  } catch (_) {
    return const OpfMetadata();
  }
}

/// All descendant elements whose *local* name matches — ignores namespace
/// prefixes so both `<dc:title>` and default-namespace `<title>` are found.
Iterable<XmlElement> _allByLocalName(XmlDocument doc, String localName) =>
    doc.findAllElements('*').where((e) => e.name.local == localName);

/// Direct element children of [parent] with the given local name.
Iterable<XmlElement> _byLocalName(XmlElement parent, String localName) =>
    parent.childElements.where((e) => e.name.local == localName);

String? _dcText(XmlElement metadata, String localName) {
  final el = _byLocalName(metadata, localName).firstOrNull;
  if (el == null) return null;
  final text = el.innerText.trim();
  return text.isEmpty ? null : text;
}
