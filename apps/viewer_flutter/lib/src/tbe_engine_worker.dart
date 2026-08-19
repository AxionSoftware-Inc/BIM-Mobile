import 'dart:async';
import 'dart:isolate';

import 'tbe_ffi.dart';

/// Keeps the native engine session off Flutter's UI isolate. All messages are
/// plain Dart values so the FFI handle never crosses an isolate boundary.
class TbeEngineWorker {
  TbeEngineWorker._(this._commandPort, this._responsePort, this._isolate) {
    _responseSubscription = _responsePort.listen(_handleResponse);
  }

  final SendPort _commandPort;
  final ReceivePort _responsePort;
  final Isolate _isolate;
  late final StreamSubscription<dynamic> _responseSubscription;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _nextRequestId = 0;
  bool _disposed = false;

  static Future<TbeEngineWorker> start() async {
    final readyPort = ReceivePort();
    final responsePort = ReceivePort();
    final isolate = await Isolate.spawn<Map<String, SendPort>>(
      _engineWorkerMain,
      <String, SendPort>{
        'ready': readyPort.sendPort,
        'responses': responsePort.sendPort,
      },
    );
    final ready = await readyPort.first;
    readyPort.close();
    if (ready is Map && ready['error'] is String) {
      responsePort.close();
      isolate.kill(priority: Isolate.immediate);
      throw TbeApiException(ready['error'] as String);
    }
    if (ready is! SendPort) {
      responsePort.close();
      isolate.kill(priority: Isolate.immediate);
      throw TbeApiException('Engine worker did not publish a command port');
    }
    return TbeEngineWorker._(ready, responsePort, isolate);
  }

  Future<String> loadProjectJson(String json) =>
      _call<String>('loadProjectJson', <String, Object?>{'json': json});

  Future<String> renderSceneJson() => _call<String>('renderSceneJson');

  Future<String> saveProjectJson() => _call<String>('saveProjectJson');

  Future<SnapResult> bestSnap({
    required int levelId,
    required double x,
    required double y,
    required double toleranceMeters,
  }) {
    return _call<Map<Object?, Object?>>('bestSnap', <String, Object?>{
      'levelId': levelId,
      'x': x,
      'y': y,
      'toleranceMeters': toleranceMeters,
    }).then(
      (value) => SnapResult(
        x: value['x']! as double,
        y: value['y']! as double,
        type: value['type']! as int,
        sourceElementId: value['sourceElementId']! as int,
        distanceMeters: value['distanceMeters']! as double,
        priority: value['priority']! as int,
      ),
    );
  }

  Future<int> createWall({
    required String name,
    required int levelId,
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    required double thicknessMeters,
    required double heightMeters,
  }) {
    return _call<int>('createWall', <String, Object?>{
      'name': name,
      'levelId': levelId,
      'startX': startX,
      'startY': startY,
      'endX': endX,
      'endY': endY,
      'thicknessMeters': thicknessMeters,
      'heightMeters': heightMeters,
    });
  }

  Future<int> createDoor({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
  }) {
    return _call<int>('createDoor', <String, Object?>{
      'name': name,
      'hostWallId': hostWallId,
      'offsetMeters': offsetMeters,
      'widthMeters': widthMeters,
      'heightMeters': heightMeters,
    });
  }

  Future<int> createWindow({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) {
    return _call<int>('createWindow', <String, Object?>{
      'name': name,
      'hostWallId': hostWallId,
      'offsetMeters': offsetMeters,
      'widthMeters': widthMeters,
      'heightMeters': heightMeters,
      'sillHeightMeters': sillHeightMeters,
    });
  }

  Future<void> moveWall(
    int wallId, {
    required double dxMeters,
    required double dyMeters,
  }) {
    return _call<void>('moveWall', <String, Object?>{
      'wallId': wallId,
      'dxMeters': dxMeters,
      'dyMeters': dyMeters,
    });
  }

  Future<void> deleteElement(int elementId) =>
      _call<void>('deleteElement', <String, Object?>{'elementId': elementId});

  Future<void> undo() => _call<void>('undo');

  Future<void> redo() => _call<void>('redo');

  Future<T> _call<T>(String operation, [Map<String, Object?>? arguments]) {
    if (_disposed) {
      return Future<T>.error(TbeApiException('Engine worker is disposed'));
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commandPort.send(<Object?>[id, operation, arguments]);
    return completer.future.then((Object? value) => value as T);
  }

  void _handleResponse(Object? message) {
    if (message is! List || message.length < 3) {
      return;
    }
    final id = message[0];
    if (id is! int) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null) {
      return;
    }
    final ok = message[1] == true;
    if (ok) {
      completer.complete(message[2]);
    } else {
      completer.completeError(TbeApiException(message[2].toString()));
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    try {
      await _call<void>('dispose');
    } finally {
      _disposed = true;
      for (final completer in _pending.values) {
        completer.completeError(TbeApiException('Engine worker stopped'));
      }
      _pending.clear();
      await _responseSubscription.cancel();
      _responsePort.close();
      _isolate.kill(priority: Isolate.immediate);
    }
  }
}

void _engineWorkerMain(Map<String, SendPort> bootstrap) {
  final readyPort = bootstrap['ready']!;
  final responsePort = bootstrap['responses']!;
  try {
    final api = TbeViewerApi.load();
    final handle = api.createSession();
    final commandPort = ReceivePort();
    readyPort.send(commandPort.sendPort);
    commandPort.listen((Object? message) {
      if (message is! List || message.length < 3 || message[0] is! int) {
        return;
      }
      final id = message[0] as int;
      final operation = message[1] as String;
      final arguments = message[2] as Map<String, Object?>?;
      try {
        final value = _executeWorkerOperation(
          api,
          handle,
          operation,
          arguments,
        );
        responsePort.send(<Object?>[id, true, value]);
        if (operation == 'dispose') {
          commandPort.close();
        }
      } catch (error) {
        responsePort.send(<Object?>[id, false, error.toString()]);
      }
    });
  } catch (error) {
    readyPort.send(<String, String>{'error': error.toString()});
  }
}

Object? _executeWorkerOperation(
  TbeViewerApi api,
  dynamic handle,
  String operation,
  Map<String, Object?>? arguments,
) {
  final args = arguments ?? const <String, Object?>{};
  switch (operation) {
    case 'loadProjectJson':
      api.loadProjectJson(handle, args['json']! as String);
      return api.getRenderSceneJson(handle);
    case 'renderSceneJson':
      return api.getRenderSceneJson(handle);
    case 'saveProjectJson':
      return api.saveProjectJson(handle);
    case 'bestSnap': {
      final snap = api.bestSnap(
        handle,
        levelId: args['levelId']! as int,
        x: args['x']! as double,
        y: args['y']! as double,
        toleranceMeters: args['toleranceMeters']! as double,
      );
      return <String, Object?>{
        'x': snap.x,
        'y': snap.y,
        'type': snap.type,
        'sourceElementId': snap.sourceElementId,
        'distanceMeters': snap.distanceMeters,
        'priority': snap.priority,
      };
    }
    case 'createWall':
      return api.createWall(
        handle,
        name: args['name']! as String,
        levelId: args['levelId']! as int,
        startX: args['startX']! as double,
        startY: args['startY']! as double,
        endX: args['endX']! as double,
        endY: args['endY']! as double,
        thicknessMeters: args['thicknessMeters']! as double,
        heightMeters: args['heightMeters']! as double,
      );
    case 'createDoor':
      return api.createDoor(
        handle,
        name: args['name']! as String,
        hostWallId: args['hostWallId']! as int,
        offsetMeters: args['offsetMeters']! as double,
        widthMeters: args['widthMeters']! as double,
        heightMeters: args['heightMeters']! as double,
      );
    case 'createWindow':
      return api.createWindow(
        handle,
        name: args['name']! as String,
        hostWallId: args['hostWallId']! as int,
        offsetMeters: args['offsetMeters']! as double,
        widthMeters: args['widthMeters']! as double,
        heightMeters: args['heightMeters']! as double,
        sillHeightMeters: args['sillHeightMeters']! as double,
      );
    case 'moveWall':
      api.moveWall(
        handle,
        args['wallId']! as int,
        dxMeters: args['dxMeters']! as double,
        dyMeters: args['dyMeters']! as double,
      );
      return null;
    case 'deleteElement':
      api.deleteElement(handle, args['elementId']! as int);
      return null;
    case 'undo':
      api.undo(handle);
      return null;
    case 'redo':
      api.redo(handle);
      return null;
    case 'dispose':
      api.destroySession(handle);
      return null;
    default:
      throw TbeApiException('Unknown engine worker operation: $operation');
  }
}
