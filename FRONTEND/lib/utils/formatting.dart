import 'package:flutter/material.dart';

String cleanError(Object error) =>
    error.toString().replaceFirst('Exception: ', '');
String money(Object? amount) {
  final value = ((amount as num?) ?? 0).round().toString();
  final grouped = value.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]} ',
  );
  return '$grouped FCFA';
}

String monthName(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ][month - 1];
void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
