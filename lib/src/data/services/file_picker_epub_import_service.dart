import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../domain/models/book.dart';
import '../../domain/models/chapter.dart';
import '../../domain/services/epub_import_service.dart';

class FilePickerEpubImportService implements EpubImportService {
  @override
  Future<Book?> importFromDeviceStorage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
      withData: false,
    );

    final pickedPath = result?.files.single.path;
    if (pickedPath == null) {
      return null;
    }

    final parserResult = await _parseEpub(pickedPath);
    final fallbackTitle = p.basenameWithoutExtension(pickedPath);
    final bookId = parserResult.identifier?.trim().isNotEmpty == true
        ? parserResult.identifier!.trim()
        : pickedPath;

    return Book(
      id: bookId,
      title: parserResult.title?.trim().isNotEmpty == true
          ? parserResult.title!.trim()
          : fallbackTitle,
      author: parserResult.author?.trim().isNotEmpty == true
          ? parserResult.author!.trim()
          : 'Unknown author',
      filePath: pickedPath,
      importedAt: DateTime.now(),
      chapters: parserResult.chapters.isNotEmpty
          ? parserResult.chapters
          : [
              Chapter(
                id: 'ch_${bookId}_0',
                bookId: bookId,
                title: 'Start',
                index: 0,
                href: 'placeholder.xhtml',
              ),
            ],
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
      final rootfileElement = containerDoc
          .findAllElements('rootfile')
          .cast<XmlElement?>()
          .firstWhere(
            (element) => element != null,
            orElse: () => null,
          );

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
      final manifestById = <String, String>{};
      if (manifestElement != null) {
        for (final item in manifestElement.findElements('item')) {
          final id = item.getAttribute('id');
          final href = item.getAttribute('href');
          if (id != null && href != null) {
            manifestById[id] = href;
          }
        }
      }

      final opfDir = p.dirname(opfPath);
      final spineElement = opfDoc.findAllElements('spine').firstOrNull;
      final chapters = <Chapter>[];
      if (spineElement != null) {
        var index = 0;
        for (final itemRef in spineElement.findElements('itemref')) {
          final idRef = itemRef.getAttribute('idref');
          final href = idRef == null ? null : manifestById[idRef];
          if (href == null) {
            continue;
          }
          final resolvedHref = p.normalize(p.join(opfDir, href));
          chapters.add(
            Chapter(
              id: 'ch_${identifier ?? filePath}_$index',
              bookId: identifier ?? filePath,
              title: 'Chapter ${index + 1}',
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
      for (final idElement in metadataElement.findElements('dc:identifier')) {
        if (idElement.getAttribute('id') == uniqueIdentifierId) {
          final text = idElement.innerText.trim();
          if (text.isNotEmpty) {
            return text;
          }
        }
      }
    }

    final fallback = metadataElement.findElements('dc:identifier').firstOrNull;
    final fallbackText = fallback?.innerText.trim();
    if (fallbackText != null && fallbackText.isNotEmpty) {
      return fallbackText;
    }

    // TODO: support EPUBs that do not use dc namespace prefixes.
    return metadataElement
        .findElements('identifier')
        .firstOrNull
        ?.innerText
        .trim();
  }

  String? _firstText(XmlElement? root, List<String> elementNames) {
    if (root == null) {
      return null;
    }

    for (final name in elementNames) {
      final text = root.findElements(name).firstOrNull?.innerText.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
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

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
