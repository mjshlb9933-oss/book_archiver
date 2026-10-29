import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:convert';
import 'dart:io';
import 'package:open_file/open_file.dart';

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
  // الكاميرا — الطريقة الآمنة
  // ═══════════════════════════════════════════
  Future<void> _captureImages() async {
    // 1. مسح الصور القديمة إذا بدأنا من جديد
    if (_capturedImages.isEmpty) {
      // لا شيء
    }

    // 2. فتح الكاميرا
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1600,
    );

    if (image == null) return;
    if (!mounted) return;

    // 3. إضافة الصورة
    setState(() => _capturedImages.add(image));

    // 4. إظهار النافذة
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
                onPressed: () {
                  Navigator.of(ctx).pop('cancel');
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('إلغاء الكل', style: TextStyle(fontSize: 15)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop('more');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('صورة أخرى'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop('done');
                },
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
      // هذه الكتلة تُنفذ بعد إغلاق النافذة
      if (!mounted) return;

      if (action == 'more') {
        // التقاط صورة أخرى
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _captureImages();
        });
      } else if (action == 'done') {
        // معالجة وحفظ
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) _processAndSavePdf();
        });
      } else {
        // إلغاء
        setState(() => _capturedImages.clear());
        _showSnack('تم إلغاء الصور', Colors.orange);
      }
    });
  }

  // ═══════════════════════════════════════════
  // معالجة الصور وإنشاء PDF
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
          final processed = img.decodeImage(bytes);
          if (processed == null) continue;

          // تدوير تلقائي
          final rotated = img.bakeOrientation(processed);

          // تحسين الوضوح
          final adjusted = img.adjustColor(
            rotated,
            brightness: 1.05,
            contrast: 1.1,
            saturation: 1.0,
          );

          // ضغط
          final jpg = img.encodeJpg(adjusted, quality: 80);

          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(10),
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

      // حفظ محلي
      final dir = Directory('/sdcard/Download/Books');
      if (!await dir.exists()) await dir.create(recursive: true);

      final fileName = 'book_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      _showSnack('✅ تم حفظ PDF: ${file.path}', Colors.green);

      // محاولة الرفع للسيرفر
      try {
        await _addBook(file.path);
        _showSnack('✅ تم رفع الكتاب للسيرفر', Colors.green);
      } catch (e) {
        _showSnack('⚠️ PDF محفوظ لكن فشل الرفع', Colors.orange);
      }

      // تفريغ
      if (mounted) {
        setState(() {
          _capturedImages.clear();
          _editingBookId = null;
          _titleCtrl.clear();
          _publisherCtrl.clear();
          _dateCtrl.clear();
        });
      }
    } catch (e) {
      _showSnack('❌ خطأ: $e', Colors.red);
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
      await _uploadPdf(bookId, pdfPath);
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
    _showSnack('عدّل البيانات ثم أضف', Colors.blue);
  }


  Future<void> _openPdf(String? pdfPath) async {
    if (pdfPath == null || pdfPath.isEmpty) {
      _showSnack('لا يوجد ملف PDF', Colors.orange);
      return;
    }

    // 1. الملف المحلي
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

    // 2. الملف على السيرفر
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
              const SizedBox(height: 16),
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
