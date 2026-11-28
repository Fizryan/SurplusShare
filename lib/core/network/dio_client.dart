import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:surplus_share/core/config/api_config.dart';
import 'package:surplus_share/core/config/logger_config.dart';
import 'package:surplus_share/core/network/auth_interceptor.dart';
import 'package:surplus_share/core/network/sanitized_log_interceptor.dart';

Dio createPublicDio(ApiConfig config, {bool enableDebugLog = kDebugMode}) {
  final dio = Dio(_baseOptions(config));
  if (enableDebugLog) {
    dio.interceptors.add(SanitizedLogInterceptor(LoggerConfig.logger));
  }
  return dio;
}

Dio createAuthenticatedDio({
  required ApiConfig config,
  required AuthInterceptor Function(Dio dio) interceptorBuilder,
  bool enableDebugLog = kDebugMode,
}) {
  final dio = Dio(_baseOptions(config));
  dio.interceptors.add(interceptorBuilder(dio));
  if (enableDebugLog) {
    dio.interceptors.add(SanitizedLogInterceptor(LoggerConfig.logger));
  }
  return dio;
}

BaseOptions _baseOptions(ApiConfig config) {
  return BaseOptions(
    baseUrl: config.baseUrl,
    connectTimeout: config.connectTimeout,
    receiveTimeout: config.receiveTimeout,
    sendTimeout: config.sendTimeout,
    headers: const <String, dynamic>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  );
}
