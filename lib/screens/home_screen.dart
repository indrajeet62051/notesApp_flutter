import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
// import 'package:flutter/services.dart';
// import 'package:document_picker/document_picker.dart';

import '../models/note.dart';

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

// ... rest of the methods (_saveNotes, _handlePermissions, _shareFile, etc.)

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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final note = _notes[index];
          return Card(
            color: note.color.withOpacity(0.2),
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text(note.title),
              subtitle: Text(
                note.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add note functionality here
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}




