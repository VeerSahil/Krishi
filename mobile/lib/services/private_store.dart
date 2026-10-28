import 'package:flutter/services.dart';

abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PrivateStore implements LocalStore {
  static const channel = MethodChannel('krishi/private_store');
  @override
  Future<String?> read(String key) =>
      channel.invokeMethod<String>('read', {'key': key});
  @override
  Future<void> write(String key, String value) =>
      channel.invokeMethod<void>('write', {'key': key, 'value': value});
}
