import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import 'tool_result.dart';

/// 加密生成工具，全部离线可用。
///
/// 密码学实现使用成熟库 `crypto`，不自行实现算法（docs/06 §6.4）。
abstract final class CryptoTools {
  static ToolResult md5(String input) {
    return ToolSuccess(crypto.md5.convert(utf8.encode(input)).toString());
  }

  static ToolResult sha1(String input) {
    return ToolSuccess(crypto.sha1.convert(utf8.encode(input)).toString());
  }

  static ToolResult sha256(String input) {
    return ToolSuccess(crypto.sha256.convert(utf8.encode(input)).toString());
  }

  static ToolResult sha512(String input) {
    return ToolSuccess(crypto.sha512.convert(utf8.encode(input)).toString());
  }

  static ToolResult hmacSha256(String key, String message) {
    final crypto.Hmac hmac = crypto.Hmac(crypto.sha256, utf8.encode(key));
    return ToolSuccess(hmac.convert(utf8.encode(message)).toString());
  }

  static ToolResult uuidV4(String countText) {
    final int count;
    if (countText.trim().isEmpty) {
      count = 1;
    } else {
      final int? parsed = int.tryParse(countText.trim());
      if (parsed == null || parsed < 1 || parsed > 1000) {
        return const ToolFailure('UUID 生成失败：数量必须是 1～1000 的整数');
      }
      count = parsed;
    }

    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int index = 0; index < count; index++) {
      final List<int> bytes = List<int>.generate(
        16,
        (_) => random.nextInt(256),
      );
      bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
      bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx
      final String hex = bytes
          .map((int b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      buffer.write(
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}',
      );
      if (index != count - 1) {
        buffer.write('\n');
      }
    }
    return ToolSuccess(buffer.toString());
  }

  static ToolResult randomPassword(String lengthText) {
    const String lower = 'abcdefghijkmnopqrstuvwxyz';
    const String upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const String digits = '23456789';
    const String symbols = '!@#\$%^&*()-_=+[]{}?';
    const String all = lower + upper + digits + symbols;

    final int length;
    if (lengthText.trim().isEmpty) {
      length = 16;
    } else {
      final int? parsed = int.tryParse(lengthText.trim());
      if (parsed == null || parsed < 4 || parsed > 256) {
        return const ToolFailure('密码生成失败：长度必须是 4～256 的整数');
      }
      length = parsed;
    }

    final Random random = Random.secure();
    final List<int> positions = List<int>.generate(
      length,
      (int index) => index,
    );
    positions.shuffle(random);

    final List<String> chars = List<String>.filled(length, '');
    chars[positions[0]] = lower[random.nextInt(lower.length)];
    chars[positions[1]] = upper[random.nextInt(upper.length)];
    chars[positions[2]] = digits[random.nextInt(digits.length)];
    chars[positions[3]] = symbols[random.nextInt(symbols.length)];
    for (int index = 4; index < length; index++) {
      chars[positions[index]] = all[random.nextInt(all.length)];
    }
    return ToolSuccess(chars.join());
  }
}
