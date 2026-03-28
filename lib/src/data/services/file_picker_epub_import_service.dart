import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

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

    // TODO: Parse EPUB metadata and NCX/Nav document.
    final bookId = DateTime.now().millisecondsSinceEpoch.toString();
    final title = p.basenameWithoutExtension(pickedPath);

    return Book(
      id: bookId,
      title: title,
      author: 'Unknown author',
      filePath: pickedPath,
      importedAt: DateTime.now(),
      chapters: [
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
}
