import '../models/book.dart';

abstract class LibraryRepository {
  Future<List<Book>> getBooks();
  Future<Book?> getBookById(String bookId);
  Future<void> addBook(Book book);
  Future<void> deleteBook(String bookId);
}
