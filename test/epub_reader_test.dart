import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/epub_reader.dart';

void main() {
  Uint8List buildEpub() {
    final Archive archive = Archive();
    archive.addFile(ArchiveFile.string('mimetype', 'application/epub+zip'));
    archive.addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?>'
            '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/content.opf',
        '<?xml version="1.0"?>'
            '<package xmlns="http://www.idpf.org/2007/opf">'
            '<metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">测试书</dc:title></metadata>'
            '<manifest>'
            '<item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine><itemref idref="c1"/></spine>'
            '</package>',
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'OEBPS/ch1.xhtml',
        '<html><body><p>第一章</p><script>alert(1)</script></body></html>',
      ),
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('解析 EPUB 标题与章节', () {
    final EpubBook book = EpubBook.parse(buildEpub());
    expect(book.title, '测试书');
    expect(book.chapterCount, 1);
    expect(book.chapterHtml(0), contains('第一章'));
    expect(book.chapterHtml(0), isNot(contains('alert')));
  });

  test('DRM EPUB 被拒绝', () {
    final Archive archive = Archive();
    archive.addFile(
      ArchiveFile.string('META-INF/encryption.xml', '<encryption/>'),
    );
    final Uint8List bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    expect(() => EpubBook.parse(bytes), throwsFormatException);
  });
}
