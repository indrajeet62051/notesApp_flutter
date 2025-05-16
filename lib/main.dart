import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:document_picker/document_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Permission.storage.request();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6B4EFF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const MyHomePage(title: 'My Notes'),
    );
  }
}

class Note {
  String title;
  String content;
  DateTime dateCreated;
  Color color;

  Note({
    required this.title,
    required this.content,
    DateTime? dateCreated,
    Color? color,
  }) : dateCreated = dateCreated ?? DateTime.now(),
       color =
           color ??
           Colors.primaries[DateTime.now().microsecond %
               Colors.primaries.length];

  Map<String, dynamic> toJson() => {
    'title': title,
    'content': content,
    'dateCreated': dateCreated.toIso8601String(),
    'color': color.value,
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    title: json['title'],
    content: json['content'],
    dateCreated: DateTime.parse(json['dateCreated']),
    color: Color(json['color']),
  );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = prefs.getString('notes');
      if (notesJson != null) {
        final List<dynamic> jsonList = json.decode(notesJson);
        setState(() {
          _notes = jsonList.map((json) => Note.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading notes: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notesJson = json.encode(
        _notes.map((note) => note.toJson()).toList(),
      );
      await prefs.setString('notes', notesJson);
    } catch (e) {
      print('Error saving notes: $e');
    }
  }

  Future<bool> _handlePermissions() async {
    // For Android 13 and above (SDK 33+)
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        final photos = await Permission.photos.status;
        final videos = await Permission.videos.status;

        if (photos.isDenied || videos.isDenied) {
          await Permission.photos.request();
          await Permission.videos.request();
        }

        return await Permission.photos.isGranted &&
            await Permission.videos.isGranted;
      }
    }

    // For Android 12 and below
    final storage = await Permission.storage.status;
    if (storage.isDenied) {
      final result = await Permission.storage.request();
      return result.isGranted;
    }

    return storage.isGranted;
  }

  Future<void> _shareFile(File file) async {
    try {
      await Share.shareXFiles([XFile(file.path)], text: 'Sharing notes backup');
    } catch (e) {
      _showSnackBar('Error sharing file: ${e.toString()}');
    }
  }

  Future<void> _exportNotes() async {
    try {
      if (!await _handlePermissions()) {
        _showSnackBar('Storage permission is required for exporting notes');
        return;
      }

      final TextEditingController fileNameController = TextEditingController(
        text: 'notes_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Show rename dialog
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Export Notes'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: fileNameController,
                    decoration: const InputDecoration(
                      labelText: 'File Name',
                      hintText: 'Enter file name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose what to do with the exported file:',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (fileNameController.text.isNotEmpty) {
                      Navigator.pop(context, {
                        'name': fileNameController.text,
                        'action': 'save',
                      });
                    }
                  },
                  child: const Text('Save to Downloads'),
                ),
                FilledButton(
                  onPressed: () {
                    if (fileNameController.text.isNotEmpty) {
                      Navigator.pop(context, {
                        'name': fileNameController.text,
                        'action': 'share',
                      });
                    }
                  },
                  child: const Text('Share'),
                ),
              ],
            ),
      );

      if (result == null) return;

      final fileName = result['name'];
      final action = result['action'];

      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final file = File('${directory.path}/$fileName.json');
      await file.writeAsString(
        json.encode(_notes.map((note) => note.toJson()).toList()),
      );

      // Ensure the file is visible in the media store
      if (Platform.isAndroid) {
        await _makeFileVisible(file);
      }

      if (action == 'share') {
        await _shareFile(file);
      } else {
        _showSnackBar('Notes exported to Downloads/$fileName.json');
      }
    } catch (e) {
      _showSnackBar('Export failed: ${e.toString()}');
    }
  }

  Future<void> _makeFileVisible(File file) async {
    try {
      if (Platform.isAndroid) {
        final mediaScanIntent = await const MethodChannel(
          'app_channel',
        ).invokeMethod('scanFile', {'path': file.path});
        print('Media scan completed: $mediaScanIntent');
      }
    } catch (e) {
      print('Error making file visible: $e');
    }
  }

  Future<void> _importNotes() async {
    try {
      if (!await _handlePermissions()) {
        _showSnackBar('Storage permission is required for importing notes');
        return;
      }

      final result = await DocumentPicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        if (await file.exists()) {
          final contents = await file.readAsString();
          try {
            final List<dynamic> jsonList = json.decode(contents);
            setState(() {
              _notes = jsonList.map((json) => Note.fromJson(json)).toList();
            });
            await _saveNotes();
            _showSnackBar('Notes imported successfully!');
          } catch (e) {
            _showSnackBar('Invalid notes file format');
          }
        } else {
          _showSnackBar('Selected file does not exist');
        }
      }
    } catch (e) {
      _showSnackBar('Import failed: ${e.toString()}');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _addOrEditNote({Note? note, int? index}) async {
    final titleController = TextEditingController(text: note?.title ?? '');
    final contentController = TextEditingController(text: note?.content ?? '');

    final result = await showDialog<Note>(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    note == null ? 'Create Note' : 'Edit Note',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      filled: true,
                    ),
                    maxLength: 50,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    decoration: InputDecoration(
                      labelText: 'Content',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      filled: true,
                    ),
                    maxLines: 5,
                    maxLength: 1000,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          if (titleController.text.trim().isNotEmpty) {
                            Navigator.pop(
                              context,
                              Note(
                                title: titleController.text.trim(),
                                content: contentController.text.trim(),
                                dateCreated: note?.dateCreated,
                                color: note?.color,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: Text(note == null ? 'Create' : 'Update'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );

    if (result != null) {
      setState(() {
        if (note == null) {
          _notes.add(result);
        } else {
          _notes[index!] = result;
        }
      });
      await _saveNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 150.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -50,
                      top: -50,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      left: -30,
                      bottom: -30,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.file_upload, color: Colors.white),
                onPressed: _exportNotes,
                tooltip: 'Export Notes',
              ),
              IconButton(
                icon: const Icon(Icons.file_download, color: Colors.white),
                onPressed: _importNotes,
                tooltip: 'Import Notes',
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver:
                _isLoading
                    ? const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                    : _notes.isEmpty
                    ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.note_outlined,
                                size: 80,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No notes yet',
                              style: TextStyle(
                                fontSize: 20,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap the + button to create a note',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    )
                    : SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.85,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final note = _notes[index];
                        return Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: note.color, width: 2),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: note.color.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Card(
                            elevation: 0,
                            color: note.color.withOpacity(0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: InkWell(
                              onTap:
                                  () =>
                                      _addOrEditNote(note: note, index: index),
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            note.title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: note.color.withOpacity(
                                                0.8,
                                              ),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline,
                                            color: note.color,
                                          ),
                                          onPressed: () async {
                                            setState(
                                              () => _notes.removeAt(index),
                                            );
                                            await _saveNotes();
                                            _showSnackBar('Note deleted');
                                          },
                                          iconSize: 20,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: Text(
                                        note.content,
                                        style: TextStyle(
                                          color: Colors.grey[800],
                                          height: 1.5,
                                        ),
                                        maxLines: 6,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: note.color.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        note.dateCreated.toString().substring(
                                          0,
                                          10,
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: note.color,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }, childCount: _notes.length),
                    ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditNote(),
        label: const Text('Add Note'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}
