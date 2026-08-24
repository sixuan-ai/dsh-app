import 'package:flutter/material.dart';

import 'src/theme.dart';

class CurrentConnectionBanner extends StatelessWidget {
  const CurrentConnectionBanner({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: P.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.success.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_tethering_rounded, color: P.success, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前连接',
                  style: TextStyle(fontSize: 11.5, color: P.textSecondary),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: P.success,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '已连接',
            style: TextStyle(
              color: P.success,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
