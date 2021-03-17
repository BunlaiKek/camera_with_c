import 'dart:io';

import 'package:flutter/material.dart';

class PreviewPage extends StatelessWidget {
  final String imagePath;

  PreviewPage({this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Image Preview'),),
      body: Center(
        child: Image.file(
          File(imagePath),
        ),
      ),
    );
  }
}
