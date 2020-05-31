import 'package:camera/camera.dart';
import 'package:firebase_ml_vision/firebase_ml_vision.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'detector_painters.dart';
import 'scanner_utils.dart';
import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart' as mqtt;

class FaceRecognition extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _FaceRecognitionState();
}

class _FaceRecognitionState extends State<FaceRecognition> {
  //camera part
  dynamic _scanResults;
  CameraController _camera;
  Detector _currentDetector = Detector.face;
  bool _isDetecting = false;
  CameraLensDirection _direction = CameraLensDirection.back;
  final FaceDetector _faceDetector = FirebaseVision.instance
      .faceDetector(FaceDetectorOptions(enableLandmarks: true));

  //mqtt part
  mqtt.MqttClient client;
  mqtt.MqttConnectionState connectionState;
  StreamSubscription subscription;
  String titleBar = 'MQTT';
  String broker = 'your_mqtt_broker';
  int port = 15323;
  String username = 'your_username';
  String passwd = 'your_password';
  String clientIdentifier = '';
  Timer mqttTimer;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() async {
    final CameraDescription description =
        await ScannerUtils.getCamera(_direction);

    _camera = CameraController(
      description,
      defaultTargetPlatform == TargetPlatform.iOS
          ? ResolutionPreset.low
          : ResolutionPreset.medium,
    );
    await _camera.initialize();
    _camera.startImageStream((CameraImage image) {
      if (_isDetecting) return;

      _isDetecting = true;

      ScannerUtils.detect(
        image: image,
        detectInImage: _faceDetector.processImage,
        imageRotation: description.sensorOrientation,
      ).then(
        (dynamic results) {
          if (_currentDetector == null) return;
          setState(() {
            _scanResults = results;
          });
        },
      ).whenComplete(() => _isDetecting = false);
    });
  }

  //painter
  Widget _buildResults() {
    CustomPainter painter;
    final Size imageSize = Size(
      _camera.value.previewSize.height,
      _camera.value.previewSize.width,
    );
    painter = FaceDetectorPainter(imageSize, _scanResults);
    return CustomPaint(
      painter: painter,
    );
  }

  Widget _buildImage() {
    return Container(
      constraints: const BoxConstraints.expand(),
      child: _camera == null
          ? Center(
              child: Container(
              child: CircularProgressIndicator(),
              alignment: Alignment.center,
            ))
          : Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CameraPreview(_camera),
                _buildResults(),
              ],
            ),
    );
  }

  void _toggleCameraDirection() async {
    if (_direction == CameraLensDirection.back) {
      _direction = CameraLensDirection.front;
    } else {
      _direction = CameraLensDirection.back;
    }

    await _camera.stopImageStream();
    await _camera.dispose();

    setState(() {
      _camera = null;
    });
    _initializeCamera();
  }

  //main page widget
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        //override back press
        onWillPop: () async {
          _sendMessage("status", "OFF");
          return true;
        },
        child: Scaffold(
            body: NestedScrollView(
                headerSliverBuilder:
                    (BuildContext context, bool innerBoxIsScrolled) {
                  return <Widget>[
                    SliverAppBar(
                        backgroundColor: client?.connectionState ==
                                mqtt.MqttConnectionState.connected
                            ? Colors.red
                            : Colors.blue,
                        expandedHeight: 110.0,
                        floating: true,
                        pinned: true,
                        title: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              SizedBox(height: 50),
                              Text(
                                _scanResults == null
                                    ? ""
                                    : _scanResults.length.toString() +
                                        " person",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20.0,
                                ),
                              ),
                              SizedBox(height: 30),
                            ]),
                        bottom: PreferredSize(
                            child: Column(children: <Widget>[
                              FloatingActionButton.extended(
                                onPressed: connection,
                                label: client?.connectionState ==
                                        mqtt.MqttConnectionState.connected
                                    ? Text("Disconnect MQTT",
                                        style: TextStyle(color: Colors.red))
                                    : Text(
                                        "Connect MQTT",
                                        style: TextStyle(color: Colors.blue),
                                      ),
                                icon: client?.connectionState ==
                                        mqtt.MqttConnectionState.connected
                                    ? Icon(
                                        Icons.cloud_done,
                                        color: Colors.red,
                                      )
                                    : Icon(
                                        Icons.cloud_off,
                                        color: Colors.blue,
                                      ),
                                backgroundColor: Colors.white,
                              ),
                              SizedBox(
                                height: 5,
                              )
                            ]),
                            preferredSize: Size.fromHeight(55.0))),
                  ];
                },
                body: Scaffold(
                  body: _buildImage(),
                  floatingActionButton: FloatingActionButton(
                    onPressed: _toggleCameraDirection,
                    child: _direction == CameraLensDirection.back
                        ? const Icon(Icons.camera_front)
                        : const Icon(Icons.camera_rear),
                  ),
                ))));
  }

  @override
  void dispose() {
    _camera.dispose().then((_) {
      _faceDetector.close();
    });
    _sendMessage("status", "OFF");
    _currentDetector = null;
    super.dispose();
  }

  //mqtt part
  void connection() {
    if (client?.connectionState == mqtt.MqttConnectionState.connected) {
      _sendMessage("status", "OFF");
      _disconnect();
      print("disconnecting");
      mqttTimer?.cancel();
    } else {
      _connect();
      print("connecting");
      Future.delayed(Duration(seconds: 1), () {
        _sendMessage("status", "ON");
      });
      mqttTimer = Timer.periodic(new Duration(seconds: 1), (timer) {
        _sendMessage("count", _scanResults.length.toString());
      });
    }
  }

  void _connect() async {
    client = mqtt.MqttClient(broker, '');
    client.port = port;
    client.logging(on: true);
    client.keepAlivePeriod = 30;
    client.onDisconnected = _onDisconnected;

    final mqtt.MqttConnectMessage connMess = mqtt.MqttConnectMessage()
        .withClientIdentifier(clientIdentifier)
        .startClean()
        .keepAliveFor(30)
        .withWillTopic('test/test')
        .withWillMessage('randi test')
        .withWillQos(mqtt.MqttQos.atMostOnce);

    print('MQTT client connecting....');
    client.connectionMessage = connMess;

    try {
      await client.connect(username, passwd);
    } catch (e) {
      print(e);
      _disconnect();
    }

    /// Check if we are connected
    if (client.connectionState == mqtt.MqttConnectionState.connected) {
      print('MQTT client connected');
      setState(() {
        connectionState = client.connectionState;
      });
    } else {
      print('ERROR: MQTT client connection failed - '
          'disconnecting, state is ${client.connectionState}');
      _disconnect();
    }
    subscription = client.updates.listen(_onMessage);
  }

  void _disconnect() {
    client.disconnect();
    _onDisconnected();
  }

  void _onDisconnected() {
    setState(() {
      connectionState = client.connectionState;
      client = null;
      subscription.cancel();
      subscription = null;
    });
    print('MQTT client disconnected');
  }

  void _onMessage(List<mqtt.MqttReceivedMessage> event) {
    print(event.length);
    final mqtt.MqttPublishMessage recMess =
        event[0].payload as mqtt.MqttPublishMessage;
    final String message =
        mqtt.MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
    print('MQTT message: topic is <${event[0].topic}>, '
        'payload is <-- ${message} -->');
    print(client.connectionState);
  }

  void _sendMessage(String topic, String msg) {
    int _qosValue = 0;
    bool _retainValue = false;
    final mqtt.MqttClientPayloadBuilder builder =
        mqtt.MqttClientPayloadBuilder();

    builder.addString(msg);
    client.publishMessage(
      topic,
      mqtt.MqttQos.values[_qosValue],
      builder.payload,
      retain: _retainValue,
    );
  }
}
