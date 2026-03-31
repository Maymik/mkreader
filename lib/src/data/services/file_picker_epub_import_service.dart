import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/services/epub_import_service.dart';

class FilePickerEpubImportService implements EpubImportService {
  @override
  Future<Book?> importFromDeviceStorage() async {
    final result = await FilePicker.platform.pickFiles(
      // Android providers may not expose .epub correctly with custom filters.
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final pickedFile = result.files.single;
    final pickedPath = pickedFile.path;
    if (pickedPath == null) {
      throw const EpubImportException(
        'Unable to access selected file path. Please pick a local EPUB file.',
      );
    }

    final isValidEpub = await _isValidEpubSelection(
      file: pickedFile,
      filePath: pickedPath,
    );
    if (!isValidEpub) {
      throw const EpubImportException(
        'Selected file is not a valid EPUB. Please choose a .epub book file.',
      );
    }

    final parserResult = await _parseEpub(pickedPath);
    final fallbackTitle = p.basenameWithoutExtension(pickedPath);
    final bookId = _buildLocalBookId();
    final persistedFilePath = await _persistEpubFile(
      sourcePath: pickedPath,
      bookId: bookId,
    );
    final normalizedSourceIdentifier = parserResult.identifier?.trim();
    final sourceIdentifier = (normalizedSourceIdentifier != null &&
            normalizedSourceIdentifier.isNotEmpty)
        ? normalizedSourceIdentifier
        : null;
    final chapters = parserResult.chapters.isNotEmpty
        ? parserResult.chapters
            .map(
              (chapter) => chapter.copyWith(
                id: 'ch_${bookId}_${chapter.index}',
                bookId: bookId,
              ),
            )
            .toList()
        : [
            Chapter(
              id: 'ch_${bookId}_0',
              bookId: bookId,
              title: 'Start',
              index: 0,
              href: 'placeholder.xhtml',
            ),
          ];

    return Book(
      id: bookId,
      sourceIdentifier: sourceIdentifier,
      title: parserResult.title?.trim().isNotEmpty == true
          ? parserResult.title!.trim()
          : fallbackTitle,
      author: parserResult.author?.trim().isNotEmpty == true
          ? parserResult.author!.trim()
          : 'Unknown author',
      filePath: persistedFilePath,
      importedAt: DateTime.now(),
      chapters: chapters,
    );
  }

  Future<_ParsedEpub> _parseEpub(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final containerEntry = _findEntry(archive, 'META-INF/container.xml');
      if (containerEntry == null) {
        return const _ParsedEpub();
      }

      final containerXml = _readString(containerEntry);
      final containerDoc = XmlDocument.parse(containerXml);
      final rootfileElement = containerDoc.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'rootfile')
          .firstOrNull;

      final opfPath = rootfileElement?.getAttribute('full-path');
      if (opfPath == null || opfPath.isEmpty) {
        return const _ParsedEpub();
      }

      final opfEntry = _findEntry(archive, opfPath);
      if (opfEntry == null) {
        return const _ParsedEpub();
      }

      final opfXml = _readString(opfEntry);
      final opfDoc = XmlDocument.parse(opfXml);
      final packageElement = opfDoc.findAllElements('package').firstOrNull;

      final metadataElement = opfDoc.findAllElements('metadata').firstOrNull;
      final title = _firstText(
        metadataElement,
        const ['dc:title', 'title'],
      );
      final author = _firstText(
        metadataElement,
        const ['dc:creator', 'creator'],
      );

      final uniqueIdAttr = packageElement?.getAttribute('unique-identifier');
      final identifier = _resolveIdentifier(
        metadataElement: metadataElement,
        uniqueIdentifierId: uniqueIdAttr,
      );

      final manifestElement = opfDoc.findAllElements('manifest').firstOrNull;
      final manifestById = <String, _ManifestItem>{};
      if (manifestElement != null) {
        for (final item in manifestElement.findElements('item')) {
          final id = item.getAttribute('id');
          final href = item.getAttribute('href');
          if (id != null && href != null) {
            manifestById[id] = _ManifestItem(
              href: href,
              mediaType: item.getAttribute('media-type'),
              properties: item.getAttribute('properties'),
            );
          }
        }
      }

      final opfDir = p.dirname(opfPath);
      final tocByHref = _readTocTitles(
        archive: archive,
        opfDir: opfDir,
        opfDoc: opfDoc,
        manifestById: manifestById,
      );
      final spineElement = opfDoc.findAllElements('spine').firstOrNull;
      final chapters = <Chapter>[];
      if (spineElement != null) {
        var index = 0;
        for (final itemRef in spineElement.findElements('itemref')) {
          final idRef = itemRef.getAttribute('idref');
          final manifestItem = idRef == null ? null : manifestById[idRef];
          if (manifestItem == null) {
            continue;
          }
          final resolvedHref =
              p.posix.normalize(p.join(opfDir, manifestItem.href));
          chapters.add(
            Chapter(
              id: 'ch_${identifier ?? filePath}_$index',
              bookId: identifier ?? filePath,
              title: tocByHref[resolvedHref] ?? 'Chapter ${index + 1}',
              index: index,
              href: resolvedHref,
            ),
          );
          index++;
        }
      }

      return _ParsedEpub(
        identifier: identifier,
        title: title,
        author: author,
        chapters: chapters,
      );
    } catch (_) {
      // TODO: add structured logging/reporting for EPUB parsing errors.
      return const _ParsedEpub();
    }
  }

  String? _resolveIdentifier({
    required XmlElement? metadataElement,
    required String? uniqueIdentifierId,
  }) {
    if (metadataElement == null) {
      return null;
    }

    if (uniqueIdentifierId != null && uniqueIdentifierId.isNotEmpty) {
      for (final idElement
          in _elementsByLocalName(metadataElement, 'identifier')) {
        if (idElement.getAttribute('id') == uniqueIdentifierId) {
          final text = idElement.innerText.trim();
          if (text.isNotEmpty) {
            return text;
          }
        }
      }
    }

    final fallback =
        _elementsByLocalName(metadataElement, 'identifier').firstOrNull;
    final fallbackText = fallback?.innerText.trim();
    if (fallbackText != null && fallbackText.isNotEmpty) {
      return fallbackText;
    }

    return null;
  }

  String? _firstText(XmlElement? root, List<String> elementNames) {
    if (root == null) {
      return null;
    }

    for (final name
        in elementNames.map((e) => e.contains(':') ? e.split(':').last : e)) {
      final text =
          _elementsByLocalName(root, name).firstOrNull?.innerText.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  Map<String, String> _readTocTitles({
    required Archive archive,
    required String opfDir,
    required XmlDocument opfDoc,
    required Map<String, _ManifestItem> manifestById,
  }) {
    final titles = <String, String>{};

    final spineElement = opfDoc.findAllElements('spine').firstOrNull;
    final tocIdRef = spineElement?.getAttribute('toc');
    final explicitNcxHref =
        tocIdRef == null ? null : manifestById[tocIdRef]?.href;
    final ncxHref = explicitNcxHref ??
        manifestById.values
            .firstWhere(
              (item) => item.mediaType == 'application/x-dtbncx+xml',
              orElse: () => const _ManifestItem(href: ''),
            )
            .href;
    if (ncxHref.isNotEmpty) {
      final ncxPath = p.posix.normalize(p.join(opfDir, ncxHref));
      titles.addAll(_parseNcxToc(archive, ncxPath, opfDir));
    }

    final navHref = manifestById.values
        .firstWhere(
          (item) => (item.properties ?? '').split(' ').contains('nav'),
          orElse: () => const _ManifestItem(href: ''),
        )
        .href;
    if (navHref.isNotEmpty) {
      final navPath = p.posix.normalize(p.join(opfDir, navHref));
      titles.addAll(_parseNavXhtmlToc(archive, navPath, opfDir));
    }

    return titles;
  }

  Map<String, String> _parseNcxToc(
      Archive archive, String ncxPath, String opfDir) {
    final entry = _findEntry(archive, ncxPath);
    if (entry == null) {
      return const {};
    }

    final map = <String, String>{};
    try {
      final doc = XmlDocument.parse(_readString(entry));
      final navPoints = doc.descendants.whereType<XmlElement>().where(
            (element) => element.name.local == 'navPoint',
          );
      for (final navPoint in navPoints) {
        final content = _elementsByLocalName(navPoint, 'content').firstOrNull;
        final rawSrc = content?.getAttribute('src');
        if (rawSrc == null || rawSrc.isEmpty) {
          continue;
        }
        final normalizedSrc = p.posix.normalize(
          p.join(opfDir, rawSrc.split('#').first),
        );
        final label = _elementsByLocalName(navPoint, 'text')
            .firstOrNull
            ?.innerText
            .trim();
        if (label != null && label.isNotEmpty) {
          map[normalizedSrc] = label;
        }
      }
    } catch (_) {
      // TODO: report malformed NCX.
    }
    return map;
  }

  Map<String, String> _parseNavXhtmlToc(
      Archive archive, String navPath, String opfDir) {
    final entry = _findEntry(archive, navPath);
    if (entry == null) {
      return const {};
    }

    final map = <String, String>{};
    try {
      final doc = XmlDocument.parse(_readString(entry));
      final links = doc.descendants.whereType<XmlElement>().where(
            (element) => element.name.local == 'a',
          );
      for (final link in links) {
        final href = link.getAttribute('href');
        if (href == null || href.isEmpty) {
          continue;
        }
        final normalizedHref = p.posix.normalize(
          p.join(opfDir, href.split('#').first),
        );
        final text = link.innerText.trim();
        if (text.isNotEmpty) {
          map[normalizedHref] = text;
        }
      }
    } catch (_) {
      // TODO: report malformed NAV document.
    }
    return map;
  }

  Iterable<XmlElement> _elementsByLocalName(
      XmlElement root, String localName) sync* {
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) {
        yield element;
      }
    }
  }

  ArchiveFile? _findEntry(Archive archive, String path) {
    final normalizedTarget = p.posix.normalize(path);
    for (final entry in archive.files) {
      final normalizedName = p.posix.normalize(entry.name);
      if (normalizedName == normalizedTarget) {
        return entry;
      }
    }
    return null;
  }

  String _readString(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) {
      return utf8.decode(content, allowMalformed: true);
    }
    return content.toString();
  }

  String _buildLocalBookId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'book_$timestamp';
  }

  Future<String> _persistEpubFile({
    required String sourcePath,
    required String bookId,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const EpubImportException(
        'Selected EPUB file is no longer available.',
      );
    }

    final appSupportDir = await getApplicationSupportDirectory();
    final booksDir = Directory(p.join(appSupportDir.path, 'books'));
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }

    final safeId = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final baseName = 'epub_$safeId';
    var targetPath = p.join(booksDir.path, '$baseName.epub');
    var counter = 1;
    while (await File(targetPath).exists()) {
      targetPath = p.join(booksDir.path, '${baseName}_$counter.epub');
      counter++;
    }

    await sourceFile.copy(targetPath);
    return targetPath;
  }

  Future<bool> _isValidEpubSelection({
    required PlatformFile file,
    required String filePath,
  }) async {
    final extension = p.extension(file.name).toLowerCase();
    final hasEpubExtension = extension == '.epub';

    final bytes = await File(filePath).readAsBytes();
    final hasZipHeader = bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (!hasZipHeader) {
      return false;
    }

    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final hasContainer =
          _findEntry(archive, 'META-INF/container.xml') != null;
      final mimetypeEntry = _findEntry(archive, 'mimetype');
      final mimetypeValue =
          mimetypeEntry == null ? null : _readString(mimetypeEntry).trim();
      final hasEpubMimetypeEntry = mimetypeValue == 'application/epub+zip';

      return hasContainer && (hasEpubExtension || hasEpubMimetypeEntry);
    } catch (_) {
      return false;
    }
  }
}

class _ParsedEpub {
  const _ParsedEpub({
    this.identifier,
    this.title,
    this.author,
    this.chapters = const [],
  });

  final String? identifier;
  final String? title;
  final String? author;
  final List<Chapter> chapters;
}

class _ManifestItem {
  const _ManifestItem({
    required this.href,
    this.mediaType,
    this.properties,
  });

  final String href;
  final String? mediaType;
  final String? properties;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class EpubImportException implements Exception {
  const EpubImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
