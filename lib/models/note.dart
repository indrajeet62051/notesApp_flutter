import 'package:flutter/material.dart';

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
  })  : dateCreated = dateCreated ?? DateTime.now(),
        color = color ??
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
