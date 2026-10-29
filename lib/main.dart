import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:open_file/open_file.dart';
import 'dart:convert';
import 'dart:io';

void main() => runApp(const BookArchiverApp());

class BookArchiverApp extends StatelessWidget {
  const BookArchiverApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'أرشيف الكتب',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF0F8F7),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _titleCtrl = TextEditingController();
  final _publisherCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<dynamic> _books = [];
  List<XFile> _capturedImages = [];
  bool _loading = false;
  int? _editingBookId;
  String? _currentPdfPath;  // مسار PDF الحالي (من الكاميرا)

  final String _apiUrl = 'http://192.168.0.101:8080/books_api/api.php';

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _publisherCtrl.dispose();
    _dateCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════
  // جلب الكتب
  // ═══════════════════════════════════════════
  Future<void> _loadBooks() async {
    setState(() => _loading = true);
    try {
      final response = await http
          .get(Uri.parse('$_apiUrl?action=list'))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['success'] == true) {
        if (mounted) setState(() => _books = data['books'] ?? []);
      }
    } catch (e) {
      _showSnack('خطأ في التحميل: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════
  // بحث
  // ═══════════════════════════════════════════
  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl?action=search&q=${Uri.encodeComponent(query)}'),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['success'] == true) {
        if (mounted) setState(() => _books = data['books'] ?? []);
      }
    } catch (e) {
      _showSnack('خطأ في البحث: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════
  // الكاميرا
  // ═══════════════════════════════════════════
  Future<void> _captureImages() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1200,
    );

    if (image == null) return;
    if (!mounted) return;

    setState(() => _capturedImages.add(image));
    if (!mounted) return;

    _showCaptureDialog();
  }

  void _showCaptureDialog() {
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.camera_alt, color: Colors.teal),
                const SizedBox(width: 8),
                Text('الصور: ${_capturedImages.length}'),
              ],
            ),
            content: const Text('هل تريد تصوير صورة أخرى؟'),
            actionsPadding: const EdgeInsets.all(12),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('إلغاء الكل'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop('more'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('صورة أخرى'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop('done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('موافق'),
              ),
            ],
          ),
        );
      },
    ).then((action) {
      if (!mounted) return;

      if (action == 'more') {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _captureImages();
        });
      } else if (action == 'done') {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _processAndSavePdf();
        });
      } else {
        setState(() => _capturedImages.clear());
        _showSnack('تم إلغاء الصور', Colors.orange);
      }
    });
  }

  // ═══════════════════════════════════════════
  // معالجة الصور — تحفظ PDF محلياً فقط
  // ═══════════════════════════════════════════
  Future<void> _processAndSavePdf() async {
    if (_capturedImages.isEmpty) {
      _showSnack('لا توجد صور', Colors.orange);
      return;
    }

    setState(() => _loading = true);
    _showSnack('⏳ جاري معالجة الصور...', Colors.blue);

    try {
      final pdf = pw.Document();
      int processedCount = 0;

      for (int i = 0; i < _capturedImages.length; i++) {
        try {
          final bytes = await _capturedImages[i].readAsBytes();
          var processed = img.decodeImage(bytes);
          if (processed == null) continue;

          if (processed.width > 1200) {
            processed = img.copyResize(
              processed,
              width: 1200,
              interpolation: img.Interpolation.average,
            );
          }

          final rotated = img.bakeOrientation(processed);
          final adjusted = img.adjustColor(
            rotated,
            brightness: 1.05,
            contrast: 1.05,
          );
          final jpg = img.encodeJpg(adjusted, quality: 70);

          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(8),
              build: (pw.Context c) => pw.Center(
                child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.contain),
              ),
            ),
          );
          processedCount++;
        } catch (e) {
          debugPrint('خطأ في صورة $i: $e');
        }
      }

      if (processedCount == 0) {
        throw Exception('فشلت معالجة جميع الصور');
      }

      final dir = Directory('/sdcard/Download/Books');
      if (!await dir.exists()) await dir.create(recursive: true);

      final fileName = 'book_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        setState(() {
          _currentPdfPath = file.path;
        });
      }

      _showSnack('✅ PDF جاهز — اضغط "إضافة" أو "تعديل" للحفظ', Colors.green);
    } catch (e) {
      _showSnack('❌ خطأ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════
  // إضافة كتاب (زر "إضافة")
  // ═══════════════════════════════════════════
  Future<void> _addNewBook() async {
    if (_titleCtrl.text.isEmpty ||
        _publisherCtrl.text.isEmpty ||
        _dateCtrl.text.isEmpty) {
      _showSnack('يرجى ملء جميع الحقول', Colors.orange);
      return;
    }

    if (_currentPdfPath == null) {
      _showSnack('يرجى التقاط صور أولاً', Colors.orange);
      return;
    }

    setState(() => _loading = true);

    try {
      // إضافة للسيرفر
      final response = await http.post(
        Uri.parse(_apiUrl),
        body: {
          'action': 'add',
          'title': _titleCtrl.text,
          'publisher': _publisherCtrl.text,
          'date': _dateCtrl.text,
          'images_count': _capturedImages.length.toString(),
        },
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (data['success'] == true) {
        final bookId = data['book']['id'];
        await _uploadPdf(bookId, _currentPdfPath!);
        await _loadBooks();
        _clearFields();
        _showSnack('✅ تمت الإضافة بنجاح', Colors.green);
      } else {
        throw Exception(data['error']);
      }
    } catch (e) {
      _showSnack('خطأ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════
  // تعديل كتاب (زر "تعديل")
  // ═══════════════════════════════════════════
  Future<void> _updateExistingBook() async {
    if (_editingBookId == null) {
      _showSnack('اختر كتاباً من الجدول أولاً', Colors.orange);
      return;
    }

    if (_titleCtrl.text.isEmpty ||
        _publisherCtrl.text.isEmpty ||
        _dateCtrl.text.isEmpty) {
      _showSnack('يرجى ملء جميع الحقول', Colors.orange);
      return;
    }

    setState(() => _loading = true);

    try {
      dynamic currentBook;
      try {
        currentBook = _books.firstWhere((b) => b['id'] == _editingBookId);
      } catch (_) {
        currentBook = null;
      }
      final oldCount = currentBook?['images_count'] ?? 0;
      final newCount = _capturedImages.isNotEmpty
          ? _capturedImages.length
          : oldCount;

      final response = await http.post(
        Uri.parse(_apiUrl),
        body: {
          'action': 'update',
          'id': _editingBookId.toString(),
          'title': _titleCtrl.text,
          'publisher': _publisherCtrl.text,
          'date': _dateCtrl.text,
          'images_count': newCount.toString(),
        },
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (data['success'] == true) {
        if (_currentPdfPath != null) {
          await _uploadPdf(_editingBookId!, _currentPdfPath!);
        }
        await _loadBooks();
        _clearFields();
        _showSnack('✅ تم التعديل بنجاح', Colors.green);
      } else {
        throw Exception(data['error']);
      }
    } catch (e) {
      _showSnack('خطأ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _uploadPdf(int bookId, String pdfPath) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.fields['action'] = 'upload_pdf';
      request.fields['book_id'] = bookId.toString();
      request.files.add(await http.MultipartFile.fromPath('pdf', pdfPath));
      await request.send().timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('PDF upload error: $e');
    }
  }

  // ═══════════════════════════════════════════
  // حذف كتاب (مع تأكيد)
  // ═══════════════════════════════════════════
  Future<void> _deleteBook(int id, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "$title" نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        body: {'action': 'delete', 'id': id.toString()},
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['success'] == true) {
        await _loadBooks();
        _showSnack('✅ تم الحذف', Colors.green);
      }
    } catch (e) {
      _showSnack('خطأ: $e', Colors.red);
    }
  }

  // ═══════════════════════════════════════════
  // فتح PDF
  // ═══════════════════════════════════════════
  Future<void> _openPdf(String? pdfPath) async {
    if (pdfPath == null || pdfPath.isEmpty) {
      _showSnack('لا يوجد ملف PDF', Colors.orange);
      return;
    }

    if (pdfPath.startsWith('/')) {
      final file = File(pdfPath);
      if (await file.exists()) {
        final result = await OpenFile.open(pdfPath);
        if (result.type != ResultType.done) {
          _showSnack('لا يمكن فتح الملف: ${result.message}', Colors.red);
        }
        return;
      }
    }

    final serverUrl = 'http://192.168.0.101:8080/books_api/$pdfPath';
    try {
      _showSnack('⏳ جاري تحميل PDF...', Colors.blue);
      final response = await http.get(Uri.parse(serverUrl));

      if (response.statusCode == 200) {
        final dir = Directory('/sdcard/Download/Books');
        if (!await dir.exists()) await dir.create(recursive: true);

        final fileName = 'downloaded_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        final result = await OpenFile.open(file.path);
        if (result.type == ResultType.done) {
          _showSnack('✅ تم فتح PDF', Colors.green);
        } else {
          _showSnack('لا يمكن فتح الملف: ${result.message}', Colors.red);
        }
      } else {
        _showSnack('فشل تحميل PDF: ${response.statusCode}', Colors.red);
      }
    } catch (e) {
      _showSnack('خطأ: $e', Colors.red);
    }
  }

  void _clearFields() {
    setState(() {
      _titleCtrl.clear();
      _publisherCtrl.clear();
      _dateCtrl.clear();
      _capturedImages.clear();
      _currentPdfPath = null;
      _editingBookId = null;
    });
  }

  void _editBook(dynamic book) {
    setState(() {
      _editingBookId = book['id'];
      _titleCtrl.text = book['title'] ?? '';
      _publisherCtrl.text = book['publisher'] ?? '';
      _dateCtrl.text = book['date'] ?? '';
      _capturedImages.clear();
      _currentPdfPath = null;
    });
    _showSnack('عدّل البيانات ثم اضغط "تعديل"', Colors.blue);
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editingBookId != null
              ? '✏️ تعديل كتاب #$_editingBookId'
              : '📚 أرشيف الكتب'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadBooks,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'موضوع الكتاب',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.book),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _publisherCtrl,
                decoration: const InputDecoration(
                  labelText: 'جهة الإصدار',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dateCtrl,
                decoration: const InputDecoration(
                  labelText: 'تاريخ الكتاب',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                  hintText: 'مثال: 2024',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loading ? null : _captureImages,
                icon: const Icon(Icons.camera_alt, size: 26),
                label: Text(
                  'تصوير (${_capturedImages.length} صورة)',
                  style: const TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              if (_currentPdfPath != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'PDF جاهز للحفظ',
                          style: TextStyle(color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _addNewBook,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _updateExistingBook,
                      icon: const Icon(Icons.edit),
                      label: const Text('تعديل'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _editingBookId != null
                          ? () => _deleteBook(_editingBookId!, _titleCtrl.text)
                          : () => _showSnack('اختر كتاباً من الجدول للحذف', Colors.orange),
                      icon: const Icon(Icons.delete),
                      label: const Text('حذف'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _clearFields,
                      icon: const Icon(Icons.clear),
                      label: const Text('تفريغ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchCtrl,
                onChanged: _search,
                decoration: const InputDecoration(
                  labelText: 'بحث',
                  hintText: 'ابحث في الموضوع أو جهة الإصدار',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_books.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('لا توجد كتب بعد', style: TextStyle(fontSize: 16)),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _books.length,
                  itemBuilder: (context, index) {
                    final book = _books[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal,
                          child: Text(
                            '#${book['id']}',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                        title: Text(book['title'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('الناشر: ${book['publisher'] ?? ''}'),
                            Text('التاريخ: ${book['date'] ?? ''}'),
                            Text('الصور: ${book['images_count'] ?? 0}'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                              tooltip: 'فتح PDF',
                              onPressed: () => _openPdf(book['pdf_path']),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editBook(book),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteBook(book['id'], book['title'] ?? ''),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
