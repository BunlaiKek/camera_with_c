import 'dart:async';
import 'dart:io';

import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

import 'package:camer_with_c/pages/preview-page.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path_provider/path_provider.dart' as pathProvider;
import 'package:image/image.dart' as imgLib;

typedef convert_func = Pointer<Uint32> Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Int32, Int32, Int32, Int32);
typedef Convert = Pointer<Uint32> Function(
    Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, int, int, int, int);

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
  final DynamicLibrary convertImageLib = Platform.isAndroid
      ? DynamicLibrary.open("libconvertImage.so")
      : DynamicLibrary.process();
  Convert conv;

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
    imgLib.Image img;
    if (Platform.isAndroid) {
      // Allocate memory for the 3 planes of the image
      Pointer<Uint8> p = allocate(count: image.planes[0].bytes.length);
      Pointer<Uint8> p1 = allocate(count: image.planes[1].bytes.length);
      Pointer<Uint8> p2 = allocate(count: image.planes[2].bytes.length);

      // Assign the planes data to the pointers of the image
      Uint8List pointerList = p.asTypedList(image.planes[0].bytes.length);
      Uint8List pointerList1 = p1.asTypedList(image.planes[1].bytes.length);
      Uint8List pointerList2 = p2.asTypedList(image.planes[2].bytes.length);
      pointerList.setRange(
          0, image.planes[0].bytes.length, image.planes[0].bytes);
      pointerList1.setRange(
          0, image.planes[1].bytes.length, image.planes[1].bytes);
      pointerList2.setRange(
          0, image.planes[2].bytes.length, image.planes[2].bytes);

      // Call the convertImage function and convert the YUV to RGB
      Pointer<Uint32> imgP = conv(
          p,
          p1,
          p2,
          image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel,
          image.planes[0].bytesPerRow,
          image.height);

      // Get the pointer of the data returned from the function to a List
      List imgData =
          imgP.asTypedList((image.planes[0].bytesPerRow * image.height));
      // Generate image from the converted data
      img = imgLib.Image.fromBytes(
          image.height, image.width, imgData);

      // Free the memory space allocated
      // from the planes and the converted data
      free(p);
      free(p1);
      free(p2);
      free(imgP);
    } else if (Platform.isIOS) {
      img = imgLib.Image.fromBytes(
        image.planes[0].bytesPerRow,
        image.height,
        image.planes[0].bytes,
        format: imgLib.Format.bgra,
      );
    }

    final rotated = imgLib.copyRotate(img, 180);

    final bytes = imgLib.encodeJpg(rotated);
    final directory = await pathProvider.getTemporaryDirectory();
    final File file = File(
        '${directory.path}/image-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return Future.value(file.path);
  }

  @override
  void initState() {
    print('state.....: initState');
    WidgetsBinding.instance.addObserver(this);
    checkPermissionStatus();
    conv = convertImageLib
        .lookup<NativeFunction<convert_func>>('convertImage')
        .asFunction<Convert>();
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
