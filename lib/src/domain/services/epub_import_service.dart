import '../models/book.dart';

abstract class EpubImportService {
  Future<Book?> importFromDeviceStorage();
}
