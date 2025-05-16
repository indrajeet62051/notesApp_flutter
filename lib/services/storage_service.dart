import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../models/note.dart';

class StorageService {
  Future<List<Note>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = prefs.getString('notes');
    if (notesJson != null) {
      final List<dynamic> jsonList = json.decode(notesJson);
      return jsonList.map((json) => Note.fromJson(json)).toList();
    }
    return [];
  }

  Future<void> saveNotes(List<Note> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = json.encode(notes.map((note) => note.toJson()).toList());
    await prefs.setString('notes', notesJson);
  }

  Future<File?> exportNotes(List<Note> notes, String fileName) async {
    if (!await _handlePermissions()) return null;

    final directory = await FilePicker.platform.getDirectoryPath();
    if (directory == null) return null;

    final file = File('$directory/$fileName.json');
    final notesJson = json.encode(notes.map((e) => e.toJson()).toList());
    await file.writeAsString(notesJson);
    return file;
  }

  Future<List<Note>?> importNotes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return null;

    final file = File(result.files.single.path!);
    final jsonString = await file.readAsString();
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((json) => Note.fromJson(json)).toList();
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
}
