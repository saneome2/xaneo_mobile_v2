import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

void main() async {
  final aesGcm = AesGcm.with256bits();
  final key = await aesGcm.newSecretKey();
  final nonce = aesGcm.newNonce();
  
  // Encrypt empty list
  final box = await aesGcm.encrypt(
    [],
    secretKey: key,
    nonce: nonce,
  );
  
  // Create combined payload
  final combined = Uint8List(nonce.length + box.cipherText.length + box.mac.bytes.length);
  combined.setRange(0, nonce.length, nonce);
  combined.setRange(nonce.length, nonce.length + box.cipherText.length, box.cipherText);
  combined.setRange(nonce.length + box.cipherText.length, combined.length, box.mac.bytes);
  
  print('Combined length: ${combined.length}');
  
  // Try to decrypt
  try {
    final decodedBox = SecretBox(
      combined.sublist(12, 12), // empty cipher
      nonce: combined.sublist(0, 12),
      mac: Mac(combined.sublist(12, 28)),
    );
    final decrypted = await aesGcm.decrypt(decodedBox, secretKey: key);
    print('Decrypted length: ${decrypted.length}');
    print('Decrypted text: ${utf8.decode(decrypted)}');
  } catch (e) {
    print('Decrypt error: $e');
  }
}
