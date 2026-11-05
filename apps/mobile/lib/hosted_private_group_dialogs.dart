import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hosted_private_groups.dart';

Future<String?> showHostedPrivateGroupTextDialog({
  required BuildContext context,
  required String title,
  required String label,
  required String hint,
  required int maxLength,
  required String submitLabel,
  required bool capitalize,
  String initialValue = '',
  bool autofocus = true,
}) {
  String value = initialValue;
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: autofocus,
        maxLength: maxLength,
        autocorrect: !capitalize,
        enableSuggestions: !capitalize,
        textCapitalization: capitalize
            ? TextCapitalization.characters
            : TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: (String nextValue) => value = nextValue,
        onFieldSubmitted: (_) => Navigator.of(dialogContext).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(value),
          child: Text(submitLabel),
        ),
      ],
    ),
  );
}

Future<void> showHostedPrivateGroupCreatedDialog({
  required BuildContext context,
  required HostedPrivateGroupCreation creation,
  required String title,
  String description = 'このIDを知っている人だけが参加できます。',
  Color? codeColor,
  Color? codeBackgroundColor,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(description),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: codeBackgroundColor ??
                  Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(
              creation.invite.code,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: codeColor ?? Theme.of(dialogContext).colorScheme.primary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Clipboard.setData(
              ClipboardData(text: creation.invite.code),
            ),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('IDをコピー'),
          ),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
