import 'package:flutter/material.dart';
import 'face_recognition_mqtt.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(home: Myhome());
  }
}

class Myhome extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _Myhome();
}

class _Myhome extends State<Myhome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: FaceRecognition());
  }
}
