import 'dart:async';
import 'dart:io';
import 'package:camer_with_c/pages/preview-page.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path_provider/path_provider.dart' as pathProvider;
import 'package:image/image.dart' as imgLib;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
        // This makes the visual density adapt to the platform that you run
        // the app on. For desktop platforms, the controls will be smaller and
        // closer together (more dense) than on mobile platforms.
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  StreamController _isCameraReadyController = BehaviorSubject<bool>();
  StreamController _allPermissionsAllowedController = BehaviorSubject<bool>();
  CameraController _cameraController;
  bool _isProcessingImage = false;

  Future<void> _initializeCamera() async {
    availableCameras().then((cameras) {
      print("List of Cameras: ${cameras.length}");
      if (cameras.length > 1) {
        _cameraController = CameraController(
            cameras[1], ResolutionPreset.medium,
            enableAudio: false);
        // _cameraController.lockCaptureOrientation(DeviceOrientation.portraitUp);
        _cameraController.initialize().then((value) async {
          print("Camera Controller initialized");
          await _cameraController
              .lockCaptureOrientation(DeviceOrientation.portraitUp);
          _isCameraReadyController.add(true);
          try {
            print('start image streaming');
            await _cameraController.startImageStream(_processImage);
            // _detectingController.add(DetectState.isScanning);
          } on CameraException catch (error) {
            print('camera error: ${error.description}');
          }
        }).catchError((error) {
          print('cannot initialize camera');
          // NotificationService.showErrorMessage(
          //     context: context, msg: error.toString());
        });
      }
    });
  }

  void _askPermission() async {
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.storage,
    ].request();
    print('statuses: $statuses');
    if (statuses[Permission.camera].isGranted &&
        statuses[Permission.storage].isGranted) {
      await _initializeCamera();
      _allPermissionsAllowedController.add(true);
    } else {
      final neededPermissions = [
        Permission.camera,
        Permission.storage,
      ];
      neededPermissions.forEach((element) async {
        if (await element.isDenied) {
          await openAppSettings();
        }
      });
    }
  }

  Future<void> checkPermissionStatus() async {
    if (await Permission.camera.isGranted &&
        await Permission.storage.isGranted) {
      await _initializeCamera();
      _allPermissionsAllowedController.add(true);
    } else {
      _allPermissionsAllowedController.add(false);
      _askPermission();
    }
  }

  void _processImage(CameraImage image) async {
    if (_isProcessingImage) {
      return;
    }
    _isProcessingImage = true;
    final String imagePath = await _convertCamerImage(image);
    if (imagePath.isNotEmpty) {
      _cameraController.stopImageStream();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) {
            return PreviewPage(
              imagePath: imagePath,
            );
          },
        ),
      );
    }
  }

  Future<String> _convertCamerImage(CameraImage image) async {
    try {
      const _shift = (0xFF << 24);
      final int width = image.width;
      final int height = image.height;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel;

      print("uvRowStride: " + uvRowStride.toString());
      print("uvPixelStride: " + uvPixelStride.toString());

      // imgLib -> Image package from https://pub.dartlang.org/packages/image
      var img = imgLib.Image(width, height); // Create Image buffer

      // Fill image buffer with plane[0] from YUV420_888
      for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
          final int uvIndex =
              uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = image.planes[0].bytes[index];
          final up = image.planes[1].bytes[uvIndex];
          final vp = image.planes[2].bytes[uvIndex];
          // Calculate pixel color
          int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
          int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
              .round()
              .clamp(0, 255);
          int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
          // color: 0x FF  FF  FF  FF
          //           A   B   G   R
          img.data[index] = _shift | (b << 16) | (g << 8) | r;
        }
      }

      final directory = await pathProvider.getTemporaryDirectory();
      final file = File(
          '${directory.path}/image-${DateTime.now().millisecondsSinceEpoch}.png');
      imgLib.PngEncoder pngEncoder = new imgLib.PngEncoder(filter: 0);
      final bytes = pngEncoder.encodeImage(img);
      await file.writeAsBytes(bytes);
      return Future.value(file.path);
    } catch (error) {
      print('converting error');
      return null;
    }
  }

  @override
  void initState() {
    print('state.....: initState');
    WidgetsBinding.instance.addObserver(this);
    checkPermissionStatus();
    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    print('state.....: $state');
    if (state == AppLifecycleState.inactive) {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      await checkPermissionStatus();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter 2'),
      ),
      body: Center(
        child: StreamBuilder(
          initialData: false,
          stream: _allPermissionsAllowedController.stream,
          builder: (pCtx, snapshot) {
            if (snapshot.data) {
              return StreamBuilder(
                stream: _isCameraReadyController.stream,
                initialData: false,
                builder: (cCtx, snapshot) {
                  if (snapshot.data) {
                    return CameraPreview(_cameraController);
                  } else {
                    return Text('Camera is not ready');
                  }
                },
              );
            } else {
              return Text('No permission allowed');
            }
          },
        ),
      ),
    );
  }
}
