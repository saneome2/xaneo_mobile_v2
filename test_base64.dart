import 'dart:convert';
import 'dart:typed_data';

void main() {
  String text = '{"type":"file","file_id":"123","file_type":"image","file_name":"...","file_size":123}';
  try {
    var normalized = text
        .replaceAll(' ', '')
        .replaceAll('\n', '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    final pad = normalized.length % 4;
    if (pad == 2) {
      normalized += '==';
    } else if (pad == 3) {
      normalized += '=';
    }
    final decoded = base64Decode(normalized);
    print('Decoded length: ${decoded.length}');
  } catch (e) {
    print('Error: $e');
  }
}
