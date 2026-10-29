import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
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
        brightness: Brightness.light,
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

  Future<void> _loadBooks() async {
    setState(() => _loading = true);
    try {
      final response = await http
          .get(Uri.parse('$_apiUrl?action=list'))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['success'] == true) {
        setState(() => _books = data['books'] ?? []);
      }
    } catch (e) {
      _showSnack('خطأ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl?action=search&q=${Uri.encodeComponent(query)}'),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data['success'] == true) {
        setState(() => _books = data['books'] ?? []);
      }
    } catch (e) {
      _showSnack('خطأ: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _captureImages() async {
    final picker = ImagePicker();

    while (true) {
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image == null) break;

      setState(() => _capturedImages.add(image));

      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text('📸 الصور: ${_capturedImages.length}'),
          content: const Text('هل تريد تصوير صورة أخرى؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('إلغاء الكل', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'more'),
              child: const Text('صورة أخرى'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'done'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('موافق'),
            ),
          ],
        ),
      );

      if (action == 'more') continue;
      if (action == 'cancel') {
        setState(() => _capturedImages.clear());
        _showSnack('تم إلغاء الصور', Colors.orange);
        break;
      }
      if (action == 'done') {
        await _processAndSavePdf();
        break;
      }
      break;
    }
  }

  Future<void> _processAndSavePdf() async {
    if (_capturedImages.isEmpty) {
      _showSnack('لا توجد صور', Colors.orange);
      return;
    }

    setState(() => _loading = true);

    try {
      final pdf = pw.Document();

      for (int i = 0; i < _capturedImages.length; i++) {
        final bytes = await _capturedImages[i].readAsBytes();
        final processed = img.decodeImage(bytes);

        if (processed == null) continue;

        // تدوير تلقائي إن لزم
        final rotated = img.bakeOrientation(processed);

        // تحسين الوضوح
        final adjusted = img.adjustColor(
          rotated,
          brightness: 1.05,
          contrast: 1.1,
          saturation: 1.0,
        );

        // تحويل إلى JPEG
        final jpg = img.encodeJpg(adjusted, quality: 85);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(10),
            build: (pw.Context ctx) => pw.Center(
              child: pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.contain),
            ),
          ),
        );
      }

      final dir = Directory('/sdcard/Download/Books');
      if (!await dir.exists()) await dir.create(recursive: true);

      final fileName =
          'book_${_editingBookId ?? DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      // إضافة الكتاب أو تعديله
      if (_editingBookId != null) {
        await _updateBook(_editingBookId!, file.path);
      } else {
        await _addBook(file.path);
      }

      _showSnack('✅ تم حفظ PDF: ${file.path}', Colors.green);

      setState(() {
        _capturedImages.clear();
        _editingBookId = null;
        _titleCtrl.clear();
        _publisherCtrl.clear();
        _dateCtrl.clear();
      });
    } catch (e) {
      _showSnack('خطأ في المعالجة: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBook(String pdfPath) async {
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
      // رفع PDF
      await _uploadPdf(bookId, pdfPath);
      await _loadBooks();
    } else {
      throw Exception(data['error']);
    }
  }

  Future<void> _updateBook(int id, String pdfPath) async {
    final response = await http.post(
      Uri.parse(_apiUrl),
      body: {
        'action': 'update',
        'id': id.toString(),
        'title': _titleCtrl.text,
        'publisher': _publisherCtrl.text,
        'date': _dateCtrl.text,
      },
    );
    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (data['success'] == true) {
      await _uploadPdf(id, pdfPath);
      await _loadBooks();
    } else {
      throw Exception(data['error']);
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

  Future<void> _deleteBook(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا الكتاب نهائياً؟'),
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

  void _clearFields() {
    setState(() {
      _titleCtrl.clear();
      _publisherCtrl.clear();
      _dateCtrl.clear();
      _capturedImages.clear();
      _editingBookId = null;
    });
    _showSnack('تم تفريغ الحقول', Colors.blue);
  }

  void _editBook(dynamic book) {
    setState(() {
      _editingBookId = book['id'];
      _titleCtrl.text = book['title'] ?? '';
      _publisherCtrl.text = book['publisher'] ?? '';
      _dateCtrl.text = book['date'] ?? '';
    });
    _showSnack('عدّل البيانات ثم اضغط تصوير لحفظ PDF جديد', Colors.blue);
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
          title: const Text('📚 أرشيف الكتب'),
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
              // الحقول الثلاثة
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

              // زر تصوير
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
              const SizedBox(height: 16),

              // أزرار الإدارة
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _capturedImages.isNotEmpty
                          ? _processAndSavePdf
                          : () => _showSnack('التقط صوراً أولاً', Colors.orange),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showSnack('اختر كتاباً من الجدول للتعديل', Colors.blue),
                      icon: const Icon(Icons.edit),
                      label: const Text('تعديل'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
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
                      onPressed: () => _showSnack('اختر كتاباً من الجدول للحذف', Colors.blue),
                      icon: const Icon(Icons.delete),
                      label: const Text('حذف'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
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
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // حقل البحث
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

              // الجدول
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
                            if (book['pdf_path'] != null)
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                tooltip: 'فتح PDF',
                                onPressed: () {
                                  _showSnack(
                                    'PDF على السيرفر: ${book['pdf_path']}',
                                    Colors.green,
                                  );
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editBook(book),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteBook(book['id']),
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
