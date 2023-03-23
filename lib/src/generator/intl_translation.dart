// Copyright 2020 The Localizely Authors. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:

//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * Neither the name of Localizely Inc. nor the names of its
//       contributors may be used to endorse or promote products derived
//       from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// Modified by Albert Wolszon.

// ignore_for_file: implementation_imports
import 'dart:convert';

import 'package:intl_translation/extract_messages.dart';
import 'package:intl_translation/generate_localized.dart';
import 'package:intl_translation/src/message_parser.dart';
import 'package:intl_translation/src/messages/literal_string_message.dart';
import 'package:intl_translation/src/messages/main_message.dart';
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';

class IntlTranslation {
  final JsonCodec jsonDecoder = const JsonCodec();

  final MessageExtraction extraction = MessageExtraction();
  final MessageGeneration generation = MessageGeneration();
  final Map<String, List<MainMessage>> messages =
      {}; // Track of all processed messages, keyed by message name

  IntlTranslation() {
    extraction.suppressWarnings = true;
    generation.useDeferredLoading = false;
    generation.generatedFilePrefix = '';
  }

  void generateFromArb(
    String outputDir,
    List<String> dartFiles,
    List<String> arbFiles,
  ) {
    final allMessages =
        dartFiles.map((file) => extraction.parseFile(File(file)));
    for (final messageMap in allMessages) {
      messageMap.forEach(
        (key, value) => messages.putIfAbsent(key, () => []).add(value),
      );
    }

    final messagesByLocale = <String, List<Map>>{};
    // Note: To group messages by locale, we eagerly read all data, which might cause a memory issue for large projects
    for (final arbFile in arbFiles) {
      _loadData(arbFile, messagesByLocale);
    }
    messagesByLocale.forEach((locale, data) {
      _generateLocaleFile(locale, data, outputDir);
    });

    final mainImportFile = File(
      path.join(
        outputDir,
        '${generation.generatedFilePrefix}messages_all.dart',
      ),
    );
    mainImportFile.writeAsStringSync(generation.generateMainImportFile());

    final localesImportFile = File(
      path.join(
        outputDir,
        '${generation.generatedFilePrefix}messages_all_locales.dart',
      ),
    );
    localesImportFile.writeAsStringSync(generation.generateLocalesImportFile());
  }

  void _loadData(String filename, Map<String, List<Map>> messagesByLocale) {
    final file = File(filename);
    final src = file.readAsStringSync();
    final data = jsonDecoder.decode(src) as Map<String, dynamic>;
    String locale = (data['@@locale'] ?? data['_locale']) as String;
    if (locale == null) {
      // Get the locale from the end of the file name. This assumes that the file
      // name doesn't contain any underscores except to begin the language tag
      // and to separate language from country. Otherwise we can't tell if
      // my_file_fr.arb is locale "fr" or "file_fr".
      final name = path.basenameWithoutExtension(file.path);
      locale = name.split('_').skip(1).join('_');
      // info(
      //     "No @@locale or _locale field found in $name, assuming '$locale' based on the file name.");
    }
    messagesByLocale.putIfAbsent(locale, () => []).add(data);
    generation.allLocales.add(locale);
  }

  void _generateLocaleFile(
    String locale,
    List<Map> localeData,
    String targetDir,
  ) {
    final translations = <TranslatedMessage>[];
    for (final jsonTranslations in localeData) {
      jsonTranslations.forEach((id, messageData) {
        final message = _recreateIntlObjects(id as String, messageData);
        if (message != null) {
          translations.add(message);
        }
      });
    }
    generation.generateIndividualMessageFile(locale, translations, targetDir);
  }

  /// Regenerate the original IntlMessage objects from the given [data]. For
  /// things that are messages, we expect [id] not to start with "@" and
  /// [data] to be a String. For metadata we expect [id] to start with "@"
  /// and [data] to be a Map or null. For metadata we return null.
  TranslatedMessage _recreateIntlObjects(String id, data) {
    if (id.startsWith('@')) return null;
    if (data == null) return null;
    final parser = MessageParser(data as String);
    var parsed = parser.pluralGenderSelectParse();
    if (parsed is LiteralString && parsed.string.isEmpty) {
      parsed = parser.nonIcuMessageParse();
    }
    return TranslatedMessage(id, parsed, messages[id]);
  }
}
