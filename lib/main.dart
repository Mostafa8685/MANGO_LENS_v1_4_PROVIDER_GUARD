import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProductFinderApp());
}

const Color kBg = Color(0xFF080D19);
const Color kPanel = Color(0xFF111A2B);
const Color kPanel2 = Color(0xFF172238);
const Color kAccent = Color(0xFF9B8CFF);
const Color kAccent2 = Color(0xFF4DD8C5);
const Color kMuted = Color(0xFF9BA9C4);
const List<String> kModels = <String>[
  'gemini-2.5-flash',
  'gemini-2.5-pro',
  'gemini-2.0-flash',
];

// App-wide preferences are shared with MaterialApp so theme and locale update instantly.
final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
final ValueNotifier<bool> appEnglish = ValueNotifier<bool>(false);

class ProductFinderApp extends StatelessWidget {
  const ProductFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([appThemeMode, appEnglish]),
      builder: (context, _) {
        return MaterialApp(
          title: 'MANGO LENS | Product Intelligence',
          debugShowCheckedModeBanner: false,
          themeMode: appThemeMode.value,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF4F6FB),
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF665BE8), brightness: Brightness.light),
            appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF4F6FB), foregroundColor: Color(0xFF172033), centerTitle: false, elevation: 0),
            inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE0E5EF))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF665BE8), width: 1.4)),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: kBg,
            colorScheme: ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.dark, surface: kPanel),
            appBarTheme: const AppBarTheme(backgroundColor: kBg, foregroundColor: Colors.white, centerTitle: false, elevation: 0),
            inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: kPanel2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              labelStyle: const TextStyle(color: kMuted), hintStyle: const TextStyle(color: Color(0xFF74819A)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF27334C))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kAccent, width: 1.4)),
            ),
            snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF26334B), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
          home: Directionality(
            textDirection: appEnglish.value ? TextDirection.ltr : TextDirection.rtl,
            child: const ProductFinderHome(),
          ),
        );
      },
    );
  }
}

class ProductFinderHome extends StatefulWidget {
  const ProductFinderHome({super.key});

  @override
  State<ProductFinderHome> createState() => _ProductFinderHomeState();
}

class _ProductFinderHomeState extends State<ProductFinderHome> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _extraController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _openAiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController(text: 'gemini-2.5-flash');
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _sellController = TextEditingController();
  final TextEditingController _feesController = TextEditingController(text: '0');
  final TextEditingController _shippingController = TextEditingController(text: '0');
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _resultKey = GlobalKey();

  File? _image;
  String _apiKey = '';
  String _openAiKey = '';
  String _apiProvider = 'gemini';
  String _model = 'gemini-2.5-flash';
  DateTime? _cooldownUntil;
  DateTime? _lastRequestAt;
  String _result = '';
  String _market = 'مصر';
  String _condition = 'غير محددة';
  String _category = 'تلقائي';
  String _detailLevel = 'سريع';
  bool _busy = false;
  bool _webSearchEnabled = false;
  String? _error;
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];
  List<String> _availableModels = List<String>.from(kModels);
  bool _checkingKey = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _extraController.dispose();
    _keyController.dispose();
    _openAiKeyController.dispose();
    _modelController.dispose();
    _costController.dispose();
    _sellController.dispose();
    _feesController.dispose();
    _shippingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> history = <Map<String, dynamic>>[];
    try {
      final raw = prefs.getString('product_history_v2');
      if (raw != null) {
        history = (jsonDecode(raw) as List<dynamic>)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {
      history = <Map<String, dynamic>>[];
    }
    if (!mounted) return;
    setState(() {
      _apiKey = prefs.getString('gemini_api_key') ?? '';
      _openAiKey = prefs.getString('openai_api_key') ?? '';
      _apiProvider = prefs.getString('ai_provider') ?? 'gemini';
      _model = prefs.getString(_apiProvider == 'openai' ? 'openai_model' : 'gemini_model') ?? (_apiProvider == 'openai' ? 'gpt-4.1-mini' : 'gemini-2.5-flash');
      final lastMs = prefs.getInt('mango_last_api_request_ms');
      if (lastMs != null) _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(lastMs);
      final cooldownMs = prefs.getInt('mango_api_cooldown_until_ms');
      if (cooldownMs != null && cooldownMs > DateTime.now().millisecondsSinceEpoch) _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(cooldownMs);
      _modelController.text = _model;
      _market = prefs.getString('product_market') ?? 'مصر';
      _condition = prefs.getString('product_condition') ?? 'غير محددة';
      _category = prefs.getString('product_category') ?? 'تلقائي';
      _detailLevel = prefs.getString('product_detail') ?? 'سريع';
      _webSearchEnabled = prefs.getBool('mango_web_search_enabled') ?? false;
      _history = history;
      appThemeMode.value = (prefs.getString('app_theme_mode') ?? 'dark') == 'light' ? ThemeMode.light : ThemeMode.dark;
      appEnglish.value = prefs.getBool('app_english') ?? false;
    });
  }

  String _t(String ar, String en) => appEnglish.value ? en : ar;

  Future<String> _checkApiKey(String key) async {
    if (key.trim().isEmpty) return _t('اكتب مفتاح API أولًا.', 'Enter an API key first.');
    try {
      // Listing models does not run a generation, so it avoids spending generation tokens.
      final response = await http.get(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=100'),
        headers: <String, String>{'x-goog-api-key': key.trim()},
      ).timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final err = data['error'];
        final message = err is Map ? (err['message']?.toString() ?? 'Unknown API error') : 'Unknown API error';
        if (response.statusCode == 429) {
          return '${_t('مفتاح API وصل إلى حد الطلبات عند اختبار قائمة النماذج. ده مش استهلاك تحليل من التطبيق؛ راجع المشروع والحصة في AI Studio.', 'The API key/project is rate-limited even for the model-list request. Check the project and quota in AI Studio.')}\n$message';
        }
        return '${_t('فشل الاختبار', 'Test failed')} (${response.statusCode}): $message';
      }
      final models = <String>[];
      final rawModels = data['models'];
      if (rawModels is List) {
        for (final item in rawModels) {
          if (item is! Map) continue;
          final methods = item['supportedGenerationMethods'];
          final name = item['name']?.toString().replaceFirst('models/', '') ?? '';
          if (name.isNotEmpty && methods is List && methods.contains('generateContent')) models.add(name);
        }
      }
      models.sort();
      if (models.isNotEmpty && mounted) setState(() => _availableModels = models);
      return _t('الاتصال ناجح. تم العثور على ${models.length} نموذجًا يدعم generateContent. لم يتم إنشاء تحليل ولم تُستهلك رموز توليد.', 'Connection successful. Found ${models.length} models supporting generateContent. No analysis was generated and no generation tokens were spent.');
    } on SocketException {
      return _t('تعذر الاتصال بالإنترنت. تحقق من الشبكة.', 'Could not connect. Check your internet connection.');
    } on FormatException {
      return _t('رد الخدمة غير مفهوم.', 'The service returned an unreadable response.');
    } catch (e) {
      return '${_t('تعذر إكمال الاختبار', 'Could not complete the test')}: $e';
    }
  }

  Future<String> _checkOpenAiKey(String key) async {
    if (key.trim().isEmpty) return _t('اكتب مفتاح OpenAI API أولًا.', 'Enter an OpenAI API key first.');
    try {
      final response = await http.get(Uri.parse('https://api.openai.com/v1/models'), headers: {'Authorization': 'Bearer ${key.trim()}'}).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = response.body;
        try { final decoded = jsonDecode(response.body); if (decoded is Map && decoded['error'] is Map) message = (decoded['error'] as Map)['message']?.toString() ?? message; } catch (_) {}
        return '${_t('فشل اختبار OpenAI', 'OpenAI test failed')} (${response.statusCode}): $message';
      }
      return _t('اتصال OpenAI ناجح. لم يتم إنشاء تحليل.', 'OpenAI connection successful. No analysis was generated.');
    } on SocketException { return _t('تعذر الاتصال بالإنترنت.', 'Could not connect to the internet.'); }
    catch (e) { return '${_t('تعذر إكمال الاختبار', 'Could not complete test')}: $e'; }
  }

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) { hash ^= unit; hash = (hash * 0x01000193) & 0x7fffffff; }
    return hash;
  }

  Future<http.Response> _sendGeminiRequest(String prompt, List<int> bytes) {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(_model)}:generateContent');
    return http.post(uri,
      headers: <String, String>{'Content-Type': 'application/json', 'x-goog-api-key': _apiKey},
      body: jsonEncode(<String, dynamic>{
        'contents': <dynamic>[{'parts': <dynamic>[{'text': prompt}, {'inline_data': {'mime_type': _mimeFor(_image!.path), 'data': base64Encode(bytes)}}]}],
        if (_webSearchEnabled) 'tools': <dynamic>[{'google_search': <String, dynamic>{}}],
        'generationConfig': <String, dynamic>{'temperature': _detailLevel == 'سريع' ? 0.2 : 0.3, 'maxOutputTokens': _detailLevel == 'سريع' ? 1100 : 2400},
      }),
    ).timeout(const Duration(seconds: 150));
  }

  Future<http.Response> _sendOpenAiRequest(String prompt, List<int> bytes) {
    final imageData = 'data:${_mimeFor(_image!.path)};base64,${base64Encode(bytes)}';
    return http.post(Uri.parse('https://api.openai.com/v1/responses'),
      headers: <String, String>{'Content-Type': 'application/json', 'Authorization': 'Bearer $_openAiKey'},
      body: jsonEncode(<String, dynamic>{
        'model': _model,
        if (_webSearchEnabled) 'tools': <dynamic>[{'type': 'web_search', 'search_context_size': 'low'}],
        if (_webSearchEnabled) 'tool_choice': 'required',
        'input': <dynamic>[{'role': 'user', 'content': <dynamic>[{'type': 'input_text', 'text': prompt}, {'type': 'input_image', 'image_url': imageData, 'detail': 'auto'}]}],
        'max_output_tokens': _detailLevel == 'سريع' ? 1100 : 2400,
      }),
    ).timeout(const Duration(seconds: 150));
  }

  String _openAiReport(Map<String, dynamic> data) {
    final direct = data['output_text']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final out = StringBuffer();
    final output = data['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map || item['content'] is! List) continue;
        for (final part in item['content'] as List) {
          if (part is Map && part['type'] == 'output_text') {
            final t = part['text']?.toString() ?? '';
            if (t.isNotEmpty) out.writeln(t);
          }
        }
      }
    }
    return out.toString().trim();
  }

  List<Map<String, String>> _openAiSources(Map<String, dynamic> data) {
    final sources = <Map<String, String>>[]; final seen = <String>{}; final output = data['output'];
    if (output is! List) return sources;
    for (final item in output) { if (item is! Map || item['content'] is! List) continue;
      for (final part in item['content'] as List) { if (part is! Map || part['annotations'] is! List) continue;
        for (final a in part['annotations'] as List) { if (a is! Map || a['type'] != 'url_citation') continue;
          final u = a['url']?.toString() ?? ''; final parsed = Uri.tryParse(u);
          if (parsed != null && (parsed.scheme == 'https' || parsed.scheme == 'http') && seen.add(u)) sources.add({'title': a['title']?.toString() ?? parsed.host, 'url': u});
        }
      }
    }
    return sources;
  }

  Future<void> _settings() async {
    _keyController.text = _apiKey;
    _openAiKeyController.text = _openAiKey;
    _modelController.text = _model;
    String selectedProvider = _apiProvider;
    bool showKey = false;
    String chosenModel = (_availableModels.contains(_model) || kModels.contains(_model)) ? _model : 'أدخل اسمًا مخصصًا';
    String? testResult;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refreshDialog) => AlertDialog(
          backgroundColor: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel,
          title: Row(children: [
            const Icon(Icons.tune_rounded, color: kAccent),
            const SizedBox(width: 10),
            Expanded(child: Text(_t('إعدادات الذكاء الاصطناعي', 'AI settings'))),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t('اختَر مزود الذكاء الاصطناعي واكتب معرّف النموذج يدويًا؛ تقدر تعدّله مستقبلًا بدون تحديث التطبيق.', 'Choose a provider and type the model ID manually; you can update it later without updating the app.'), style: const TextStyle(color: kMuted, height: 1.5)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: selectedProvider,
                isExpanded: true,
                decoration: InputDecoration(labelText: _t('مزود الذكاء الاصطناعي', 'AI provider')),
                items: const [DropdownMenuItem(value: 'gemini', child: Text('Google Gemini')), DropdownMenuItem(value: 'openai', child: Text('OpenAI API'))],
                onChanged: (value) {
                  if (value == null) return;
                  refreshDialog(() {
                    selectedProvider = value;
                    _modelController.text = value == 'openai' ? 'gpt-4.1-mini' : 'gemini-2.5-flash';
                    chosenModel = 'أدخل اسمًا مخصصًا';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyController,
                obscureText: !showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Gemini API Key',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(tooltip: showKey ? 'إخفاء المفتاح' : 'إظهار المفتاح', onPressed: () => refreshDialog(() => showKey = !showKey), icon: Icon(showKey ? Icons.visibility_off : Icons.visibility)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _openAiKeyController,
                obscureText: !showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: 'OpenAI API Key', prefixIcon: const Icon(Icons.key_outlined), hintText: 'sk-…'),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: chosenModel,
                isExpanded: true,
                decoration: InputDecoration(labelText: _t('نموذج جاهز', 'Available model')),
                items: <String>{..._availableModels, ...kModels, 'أدخل اسمًا مخصصًا'}.toList().map((m) => DropdownMenuItem<String>(value: m, child: Text(m))).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  refreshDialog(() {
                    chosenModel = value;
                    if (value != 'أدخل اسمًا مخصصًا') _modelController.text = value;
                    else _modelController.clear();
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _modelController,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: _t('اسم النموذج المستخدم فعليًا', 'Model ID to use'),
                  hintText: selectedProvider == 'openai' ? 'gpt-4.1-mini' : 'gemini-2.5-flash',
                  prefixIcon: Icon(Icons.memory_rounded),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF202A41), borderRadius: BorderRadius.circular(14)),
                child: const Text(
                  'أدخل مفتاح المزود الذي اخترته. المفاتيح محفوظة محليًا لهذا الجهاز فقط، وده مناسب للتجربة الشخصية؛ إصدار عام لشركة مانجو يحتاج خادمًا وسيطًا يحمي المفاتيح ويحدد استهلاك كل مستخدم.',
                  style: TextStyle(color: kMuted, fontSize: 12, height: 1.6),
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 6),
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.dark_mode_outlined),
                title: Text(_t('الوضع الداكن', 'Dark theme')),
                subtitle: Text(_t('أوقفه لاستخدام الوضع الفاتح', 'Turn off to use light theme')),
                value: appThemeMode.value == ThemeMode.dark,
                onChanged: (value) async {
                  appThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('app_theme_mode', value ? 'dark' : 'light');
                  refreshDialog(() {});
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.language_rounded),
                title: Text(_t('اللغة الإنجليزية', 'English language')),
                subtitle: Text(_t('العربية هي اللغة الأساسية', 'Arabic is the default language')),
                value: appEnglish.value,
                onChanged: (value) async {
                  appEnglish.value = value;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('app_english', value);
                  refreshDialog(() {});
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _checkingKey ? null : () async {
                  refreshDialog(() { _checkingKey = true; testResult = null; });
                  final result = selectedProvider == 'gemini' ? await _checkApiKey(_keyController.text) : await _checkOpenAiKey(_openAiKeyController.text);
                  if (!ctx.mounted) return;
                  refreshDialog(() {
                    _checkingKey = false;
                    testResult = result;
                    if (selectedProvider == 'gemini' && _availableModels.isNotEmpty && !_availableModels.contains(_modelController.text.trim())) {
                      _modelController.text = _availableModels.first;
                      chosenModel = _availableModels.first;
                    }
                  });
                },
                icon: _checkingKey ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check_rounded),
                label: Text(_checkingKey ? _t('جاري اختبار الاتصال...', 'Testing connection...') : _t('اختبار الاتصال', 'Test connection')),
              ),
              if (testResult != null) ...[
                const SizedBox(height: 8),
                Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: appThemeMode.value == ThemeMode.light ? const Color(0xFFF0F2F8) : kPanel2, borderRadius: BorderRadius.circular(12)), child: Text(testResult!, style: const TextStyle(fontSize: 12, height: 1.5))),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: appThemeMode.value == ThemeMode.light ? const Color(0xFFF0F2F8) : kPanel2, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_t('عن التطبيق', 'About this app'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(_t('صناعة شركة مانجو', 'Made by MANGO Company'), style: const TextStyle(fontSize: 13)),
                  Text(_t('المؤسس: مصطفى ماجد', 'Founder: Mostafa Maged'), style: const TextStyle(color: kMuted, fontSize: 12)),
                  Text('MANGO LENS • v1.4', style: const TextStyle(color: kMuted, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _openUrl(selectedProvider == 'openai' ? 'https://platform.openai.com/api-keys' : 'https://aistudio.google.com/apikey'),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(selectedProvider == 'openai' ? _t('فتح منصة OpenAI', 'Open OpenAI platform') : _t('فتح Google AI Studio', 'Open Google AI Studio')),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('إلغاء', 'Cancel'))),
            FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.save_outlined), label: Text(_t('حفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (saved != true) return;

    final key = _keyController.text.trim();
    final openAiKey = _openAiKeyController.text.trim();
    final model = _modelController.text.trim().replaceAll('models/', '');
    if (model.isEmpty) {
      _message('اكتب معرّف النموذج أولًا');
      return;
    }
    if (selectedProvider == 'gemini' && key.isEmpty) { _message('أدخل مفتاح Gemini API'); return; }
    if (selectedProvider == 'openai' && openAiKey.isEmpty) { _message('أدخل مفتاح OpenAI API'); return; }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    await prefs.setString('openai_api_key', openAiKey);
    await prefs.setString('ai_provider', selectedProvider);
    await prefs.setString(selectedProvider == 'openai' ? 'openai_model' : 'gemini_model', model);
    if (!mounted) return;
    setState(() {
      _apiKey = key;
      _openAiKey = openAiKey;
      _apiProvider = selectedProvider;
      _model = model;
    });
    _message('تم حفظ الإعدادات');
  }

  Future<void> _chooseImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 74,
        maxWidth: 1400,
        maxHeight: 1400,
      );
      if (picked == null) return;
      setState(() {
        _image = File(picked.path);
        _result = '';
        _error = null;
      });
    } catch (_) {
      _message('تعذر فتح الكاميرا أو الصور. تأكد من أذونات الجهاز ثم حاول مرة أخرى.');
    }
  }

  void _imageOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(children: [
            const ListTile(title: Text('اختر صورة المنتج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF29264D), child: Icon(Icons.camera_alt_rounded, color: kAccent)),
              title: const Text('التقاط صورة بالكاميرا'),
              subtitle: const Text('صوّر المنتج والملصق بوضوح'),
              onTap: () { Navigator.pop(ctx); _chooseImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: Color(0xFF163D3A), child: Icon(Icons.photo_library_outlined, color: kAccent2)),
              title: const Text('اختيار صورة من المعرض'),
              subtitle: const Text('يمكن اختيار صورة ملتقطة سابقًا'),
              onTap: () { Navigator.pop(ctx); _chooseImage(ImageSource.gallery); },
            ),
          ]),
        ),
      ),
    );
  }

  String _mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  String _makePrompt(String extra) {
    final answerLanguage = appEnglish.value ? 'clear English' : 'العربية الواضحة';
    final detail = _detailLevel == 'سريع'
        ? 'اكتب تقريرًا متوسط الطول يركز على التعرف والسعر وأفضل روابط الشراء والتحذيرات الأساسية.'
        : 'اكتب تقريرًا عميقًا منظمًا، غنيًا بالمعلومات، مع أقسام واضحة وجداول Markdown عند فائدتها.';
    return '''أنت مساعد متخصص في التعرف على المنتجات وتحليلها. حلل صورة المنتج المرفقة. ${_webSearchEnabled ? 'استخدم أداة البحث على الويب المتاحة للعثور على عروض حديثة فعلية.' : 'لا تستخدم البحث على الويب في هذه العملية، ولا تدّع أنك تحققت من الأسعار الحالية؛ وضّح أن أي سعر هو تقديري أو غير متحقق منه.'} أجب بـ $answerLanguage، ولا تملأ أي فراغ بمعلومات مختلقة.

سوق الشراء المستهدف: $_market.
حالة المنتج التي يريد المستخدم المقارنة على أساسها: $_condition.
التصنيف المفضل: $_category.
${extra.isNotEmpty ? 'تفاصيل إضافية من المستخدم: $extra' : ''}

$detail

قسّم الإجابة بهذه الأقسام:
## 1. تحديد هوية المنتج
الاسم المرجح، العلامة التجارية، الطراز أو رقم القطعة إن أمكن، وما الذي في الصورة يدعم هذا التعرف. أعط درجة ثقة تقريبية واطلب صورة إضافية إذا لم تكفِ الصورة.
## 2. وصف ومواصفات
الغرض والاستخدام، المواصفات التي أمكن التحقق منها، الخامات/المكونات، المقاس أو السعة إن أمكن، الشركة المصنعة وبلد المنشأ وبلد التصنيع عند توفر دليل. ميّز الحقائق من التقديرات.
## 3. الأسعار والعروض
أقل سعر موثوق وجدته في سوق $_market، ومتوسط/نطاق الأسعار إن توفرت عدة عروض، والعملة، وحالة كل عرض (جديد أو مستعمل أو مجدد)، وتاريخ التحقق. اذكر هل السعر يشمل الشحن والضرائب إن كان ذلك معروفًا. لا تخلط بين سعر دولي وسعر السوق المستهدف، ولا تخترع سعرًا أو سعر صرف.
## 4. روابط الشراء والمقارنة
اعرض روابط مباشرة موثوقة قدر الإمكان، واسم المتجر والسعر والحالة بجوار كل رابط. وضّح إن كان الرابط صفحة منتج مؤكدة أم نتيجة بحث عامة، ولا تنشئ روابط وهمية.
## 5. الندرة والقيمة لهواة الاقتناء
هل المنتج شائع أو قديم أو إصدار محدود أو نادر؟ استخدم أدلة مثل تاريخ الإصدار، أرقام الإنتاج أو توافر عروض فعلية. إذا لم توجد أدلة كافية فاكتب أن الندرة غير مؤكدة. لا تستنتج الندرة من غرابة الشكل وحدها.
## 6. الأصالة والحالة
علامات أو أرقام يمكن فحصها، وما الذي لا يمكن إثباته من صورة واحدة. لا تؤكد الأصالة نهائيًا من الصورة وحدها. اذكر التلف الظاهر فقط إذا أمكن رؤيته.
## 7. نصائح قبل الشراء
ما المعلومات أو الصور الإضافية التي ينبغي طلبها، وأبرز مخاطر التقليد أو اختلاف النسخ، وهل يمكن الحكم أن السعر مناسب بناءً على مصادر متاحة.
## 8. خلاصة سريعة
لخص الاسم المرجح، أدنى سعر موثوق وجدته أو صرّح بعدم توفره، درجة الثقة، وخطوة التحقق التالية.

قواعد دقة إلزامية:
- ${_webSearchEnabled ? 'استخدم نتائج البحث الفعلية واستشهد بالمصادر أو روابطها.' : 'إذا لم يكن البحث على الويب مفعّلًا، لا تخترع مصادر أو أسعارًا مباشرة؛ صرّح بوضوح أن السعر غير متحقق منه حاليًا.'}
- لا تقل إنك فحصت المخزون أو السعر في وقت محدد إلا إذا أظهرت النتائج ذلك فعلًا.
- أظهر تاريخ الفحص بأنه وقت إنشاء هذا التقرير، وليس ضمانًا لبقاء السعر.
- افصل بوضوح بين المعلومة المؤكدة والتقدير.
- إذا لم تتعرف على المنتج، اقترح ما يجب تصويره أو رقم الملصق المطلوب.
''';
  }

  List<Map<String, String>> _groundingSources(Map<String, dynamic> data) {
    final sources = <Map<String, String>>[];
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) return sources;
    final candidate = Map<String, dynamic>.from(candidates.first as Map);
    final meta = candidate['groundingMetadata'];
    if (meta is! Map) return sources;
    final chunks = meta['groundingChunks'];
    if (chunks is! List) return sources;
    final seen = <String>{};
    for (final item in chunks) {
      if (item is! Map) continue;
      final web = item['web'];
      if (web is! Map) continue;
      final uri = web['uri']?.toString() ?? '';
      final title = web['title']?.toString().trim() ?? '';
      final parsed = Uri.tryParse(uri);
      if (parsed == null || (parsed.scheme != 'https' && parsed.scheme != 'http') || !seen.add(uri)) continue;
      sources.add(<String, String>{'title': title.isEmpty ? parsed.host : title, 'url': uri});
    }
    return sources;
  }

  Future<void> _analyze() async {
    if (_image == null) {
      _message(_t('صوّر المنتج أو اختر صورة أولًا', 'Capture or select a product image first'));
      return;
    }
    final activeKey = _apiProvider == 'openai' ? _openAiKey : _apiKey;
    if (activeKey.isEmpty) {
      _message(_t('أضف مفتاح API للمزود المختار من الإعدادات أولًا', 'Add an API key for the selected provider in Settings first'));
      await _settings();
      return;
    }
    if (_busy) return;
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    setState(() { _busy = true; _error = null; _result = ''; });
    try {
      final bytes = await _image!.readAsBytes();
      final prompt = _makePrompt(_extraController.text.trim());
      final requestKey = '${_stableHash(base64Encode(bytes))}|$_apiProvider|$_model|$_market|$_condition|$_category|$_detailLevel|$_webSearchEnabled|${_extraController.text.trim()}';
      if (prefs.getString('mango_cached_request_key') == requestKey) {
        final cached = prefs.getString('mango_cached_report') ?? '';
        if (cached.isNotEmpty) {
          if (mounted) setState(() => _result = '$cached\n\n---\n${_t('ملاحظة: هذه نتيجة محفوظة محليًا من تحليل سابق وليست فحصًا جديدًا للسعر.', 'Note: this is a locally cached result from a previous analysis, not a fresh price check.')}');
          _message(_t('استخدمت النتيجة المحفوظة لتوفير حصة API.', 'Used the cached result to save API quota.'));
          return;
        }
      }
      if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) {
        final seconds = _cooldownUntil!.difference(now).inSeconds + 1;
        _message(_t('تم إيقاف الطلبات مؤقتًا بعد حد الاستخدام. جرّب بعد $seconds ثانية.', 'Requests are paused after a rate limit. Try again in $seconds seconds.'));
        return;
      }
      if (_lastRequestAt != null) {
        final remaining = const Duration(seconds: 15) - now.difference(_lastRequestAt!);
        if (remaining > Duration.zero) {
          _message(_t('لتوفير الحصة، استنى ${remaining.inSeconds + 1} ثانية قبل التحليل التالي.', 'To save quota, wait ${remaining.inSeconds + 1} seconds before the next scan.'));
          return;
        }
      }
      _lastRequestAt = now;
      await prefs.setInt('mango_last_api_request_ms', now.millisecondsSinceEpoch);
      final response = _apiProvider == 'openai' ? await _sendOpenAiRequest(prompt, bytes) : await _sendGeminiRequest(prompt, bytes);

      Map<String, dynamic> data;
      try {
        data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw Exception('وصل رد غير مفهوم من الخدمة. حاول مرة أخرى بعد قليل.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorObject = data['error'];
        final apiMessage = errorObject is Map ? (errorObject['message']?.toString() ?? 'خطأ غير معروف') : (errorObject?.toString() ?? 'خطأ غير معروف');
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('مفتاح API غير صحيح أو غير مسموح له باستخدام هذا النموذج. راجع المفتاح واسم النموذج.');
        }
        if (response.statusCode == 429) {
          final retryAfter = int.tryParse(response.headers['retry-after'] ?? '') ?? 90;
          final cooldownSeconds = retryAfter < 90 ? 90 : (retryAfter > 3600 ? 3600 : retryAfter);
          _cooldownUntil = DateTime.now().add(Duration(seconds: cooldownSeconds));
          await prefs.setInt('mango_api_cooldown_until_ms', _cooldownUntil!.millisecondsSinceEpoch);
          final diagnostic = apiMessage;
          throw Exception('${_t('وصلت لحد استخدام مزود الذكاء الاصطناعي. أوقفنا المحاولات تلقائيًا لتجنب زيادة الضغط. التفاصيل:', 'The AI provider rate limit was reached. Automatic attempts are paused to avoid further requests. Details:')}\n$diagnostic\n\n${_t('لو السبب حصة يومية، قد تحتاج الانتظار حتى إعادة ضبطها؛ فترة الانتظار القصيرة لا تعيد الحصة اليومية.', 'If the daily quota is exhausted, you may need to wait for its reset; a short cooldown does not reset daily quota.')}');
        }
        if (response.statusCode == 404) throw Exception('لم يتم العثور على النموذج "$_model". تحقق من معرّف النموذج.');
        throw Exception('خطأ ${_apiProvider == 'openai' ? 'OpenAI' : 'Gemini'} (${response.statusCode}): $apiMessage');
      }

      String report;
      List<Map<String, String>> sources;
      if (_apiProvider == 'openai') {
        report = _openAiReport(data);
        sources = _openAiSources(data);
      } else {
        final candidates = data['candidates'];
        if (candidates is! List || candidates.isEmpty || candidates.first is! Map) {
          final feedback = data['promptFeedback'];
          if (feedback is Map && feedback['blockReason'] != null) throw Exception('لم تتم معالجة الطلب بسبب قيود السلامة: ${feedback['blockReason']}');
          throw Exception('لم يرجع النموذج تقريرًا. جرّب صورة أوضح أو نموذجًا آخر.');
        }
        final candidate = Map<String, dynamic>.from(candidates.first as Map);
        final content = candidate['content']; final parts = content is Map ? content['parts'] : null;
        report = parts is List ? parts.whereType<Map>().map((p) => p['text']?.toString() ?? '').where((v) => v.isNotEmpty).join('\n\n').trim() : '';
        sources = _groundingSources(data);
      }
      if (report.isEmpty) throw Exception('التقرير فارغ. قد يكون النموذج قد أنهى الطلب دون نص؛ جرّب مرة أخرى.');

      final output = StringBuffer(report);
      if (sources.isNotEmpty) {
        output.write('\n\n## ${_t('مصادر البحث التي أعادها مزود الذكاء الاصطناعي', 'Web sources returned by the AI provider')}\n');
        for (final source in sources.take(10)) {
          output.write('\n- [${source['title']}](${source['url']})');
        }
      }
      final finalReport = output.toString();
      await prefs.setString('mango_cached_request_key', requestKey);
      await prefs.setString('mango_cached_report', finalReport);
      await prefs.remove('mango_api_cooldown_until_ms');
      _cooldownUntil = null;
      if (!mounted) return;
      setState(() => _result = finalReport);
      await _saveHistory(finalReport);
      HapticFeedback.mediumImpact();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_resultKey.currentContext != null) {
          Scrollable.ensureVisible(_resultKey.currentContext!, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.04);
        }
      });
    } on SocketException {
      if (mounted) setState(() => _error = 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وحاول مجددًا.');
    } on HttpException {
      if (mounted) setState(() => _error = 'حدثت مشكلة أثناء الاتصال بخدمة البحث. حاول مرة أخرى.');
    } on FormatException {
      if (mounted) setState(() => _error = 'وصل رد غير مفهوم من الخدمة. حاول مرة أخرى.');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _titleFromReport(String report) {
    for (final line in report.split('\n')) {
      final cleaned = line.replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s*'), '').replaceAll('*', '').trim();
      if (cleaned.isNotEmpty && !cleaned.startsWith('[') && !cleaned.startsWith('- ')) {
        return cleaned.length > 72 ? '${cleaned.substring(0, 69)}…' : cleaned;
      }
    }
    return 'تحليل منتج';
  }

  Future<void> _saveHistory(String report) async {
    final entry = <String, dynamic>{
      'title': _titleFromReport(report),
      'report': report,
      'createdAt': DateTime.now().toIso8601String(),
      'market': _market,
      'model': _model,
    };
    final next = <Map<String, dynamic>>[entry, ..._history].take(25).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('product_history_v2', jsonEncode(next));
    if (!mounted) return;
    setState(() => _history = next);
  }

  Future<void> _openHistory() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel,
        title: Row(children: [
          Expanded(child: Text(_t('سجل عمليات الفحص', 'Scan history'))),
          if (_history.isNotEmpty)
            IconButton(tooltip: _t('مسح السجل', 'Clear history'), onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (confirmCtx) => AlertDialog(
                  backgroundColor: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel2,
                  title: Text(_t('مسح سجل الفحص؟', 'Clear scan history?')),
                  content: Text(_t('سيتم حذف التقارير المحفوظة محليًا من هذا الجهاز.', 'Saved reports will be deleted from this device.')),
                  actions: [TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(confirmCtx, true), child: const Text('مسح'))],
                ),
              );
              if (confirm == true) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('product_history_v2');
                if (mounted) setState(() => _history = <Map<String, dynamic>>[]);
                if (ctx.mounted) Navigator.pop(ctx);
                _message('تم مسح السجل');
              }
            }, icon: const Icon(Icons.delete_sweep_outlined)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: _history.isEmpty
              ? const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history_rounded, size: 48, color: kMuted), SizedBox(height: 12), Text('لا توجد تقارير محفوظة حتى الآن'), SizedBox(height: 6), Text('بعد تحليل أول منتج سيظهر تقريرك هنا.', style: TextStyle(color: kMuted, fontSize: 12))]))
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 430),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const Divider(color: Color(0xFF27334C)),
                    itemBuilder: (ctx, index) {
                      final item = _history[index];
                      final date = DateTime.tryParse(item['createdAt']?.toString() ?? '')?.toLocal();
                      final dateLabel = date == null ? '' : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}  ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(backgroundColor: Color(0xFF29264D), child: Icon(Icons.document_scanner_outlined, color: kAccent)),
                        title: Text(item['title']?.toString() ?? 'تحليل منتج', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${item['market'] ?? 'السوق غير محدد'}${dateLabel.isEmpty ? '' : ' • $dateLabel'}', style: const TextStyle(color: kMuted, fontSize: 11)),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() => _result = item['report']?.toString() ?? '');
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_resultKey.currentContext != null) Scrollable.ensureVisible(_resultKey.currentContext!, duration: const Duration(milliseconds: 400), alignment: 0.05);
                          });
                        },
                      );
                    },
                  ),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('إغلاق', 'Close')))],
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      try {
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) _message('تعذر فتح الرابط على هذا الجهاز');
      } catch (_) {
        _message('تعذر فتح الرابط');
      }
    } else {
      _message('الرابط غير صالح');
    }
  }

  Future<void> _saveChoice(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  double _number(TextEditingController controller) => double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  Widget _profitCalculator() {
    final cost = _number(_costController);
    final sell = _number(_sellController);
    final fees = _number(_feesController);
    final shipping = _number(_shippingController);
    final profit = sell - cost - fees - shipping;
    final margin = sell > 0 ? (profit / sell) * 100 : 0.0;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: appThemeMode.value == ThemeMode.light ? const Color(0xFFE0E5EF) : const Color(0xFF2A3852)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle(_t('حاسبة ربح التاجر', 'Seller profit calculator'), _t('احسب هامش الربح بدون أي طلبات ذكاء اصطناعي أو استهلاك للحصة.', 'Calculate profit without any AI requests or quota usage.'), Icons.calculate_outlined),
        Row(children: [
          Expanded(child: TextField(controller: _costController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: _t('سعر الشراء', 'Cost price'), prefixIcon: const Icon(Icons.shopping_bag_outlined)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _sellController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: _t('سعر البيع', 'Sale price'), prefixIcon: const Icon(Icons.sell_outlined)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _feesController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: _t('عمولات ومصاريف', 'Fees & expenses'), prefixIcon: const Icon(Icons.receipt_long_outlined)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _shippingController, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: _t('الشحن', 'Shipping'), prefixIcon: const Icon(Icons.local_shipping_outlined)))),
        ]),
        const SizedBox(height: 13),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: profit >= 0 ? const Color(0x1E32B987) : const Color(0x20F06475), borderRadius: BorderRadius.circular(15)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_t('صافي الربح المتوقع', 'Estimated net profit'), style: const TextStyle(color: kMuted, fontSize: 12)), const SizedBox(height: 4), Text(profit.toStringAsFixed(2), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: profit >= 0 ? const Color(0xFF31C48D) : const Color(0xFFFF7A8A)))])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)), child: Column(children: [Text(_t('هامش الربح', 'Profit margin'), style: const TextStyle(fontSize: 10, color: kMuted)), const SizedBox(height: 3), Text('${margin.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))])),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String title, String subtitle, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFF29264D), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: kAccent)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 12, height: 1.45)),
        ])),
      ]),
    );
  }

  String _translateOption(String item) {
    const translations = <String, String>{
      'مصر': 'Egypt', 'السعودية': 'Saudi Arabia', 'الإمارات': 'United Arab Emirates', 'الكويت': 'Kuwait', 'قطر': 'Qatar', 'الأردن': 'Jordan', 'الولايات المتحدة': 'United States', 'المملكة المتحدة': 'United Kingdom', 'السوق العالمي': 'Global market',
      'تلقائي': 'Automatic', 'إلكترونيات': 'Electronics', 'أجهزة منزلية': 'Home appliances', 'ملابس وأحذية': 'Clothing & shoes', 'عطور ومستحضرات': 'Perfumes & cosmetics', 'ألعاب ومقتنيات': 'Toys & collectibles', 'تحف وأنتيكات': 'Antiques', 'كتب ومطبوعات': 'Books & prints', 'أدوات ومعدات': 'Tools & equipment', 'أخرى': 'Other',
      'غير محددة': 'Unspecified', 'جديد': 'New', 'مستعمل': 'Used', 'مجدد / Refurbished': 'Refurbished', 'قطعة لهواة الاقتناء': 'Collectible', 'سريع': 'Fast', 'تفصيلي': 'Detailed',
    };
    return appEnglish.value ? (translations[item] ?? item) : item;
  }

  Widget _dropdown({required String label, required String value, required List<String> items, required ValueChanged<String?> onChanged, IconData? icon}) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : items.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon, size: 19)),
      items: items.map((item) => DropdownMenuItem<String>(value: item, child: Text(_translateOption(item), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _featurePill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(50), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: kAccent2), const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFFD8E0F4)))],),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kAccent, Color(0xFF665BE8)]), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.center_focus_strong_rounded, color: Colors.white)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('MANGO LENS', style: TextStyle(fontSize: 16, letterSpacing: 1.1, fontWeight: FontWeight.w900)), Text(_t('كاشف المنتجات الذكي', 'AI Product Finder'), style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.normal))])),
        ]),
        actions: [
          IconButton(tooltip: _t('سجل الفحص', 'Scan history'), onPressed: _openHistory, icon: Badge(isLabelVisible: _history.isNotEmpty, label: Text('${_history.length}'), child: const Icon(Icons.history_rounded))),
          IconButton(tooltip: _t('الإعدادات', 'Settings'), onPressed: _settings, icon: const Icon(Icons.settings_outlined)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF29245C), Color(0xFF152D42), Color(0xFF102D33)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFF514B8C).withValues(alpha: 0.55)),
                boxShadow: const [BoxShadow(color: Color(0x20211A63), blurRadius: 24, offset: Offset(0, 10))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: kAccent2.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(40)), child: const Row(children: [Icon(Icons.auto_awesome, size: 13, color: kAccent2), SizedBox(width: 5), Text('AI PRODUCT INTELLIGENCE', style: TextStyle(fontSize: 9, letterSpacing: 0.7, fontWeight: FontWeight.bold, color: kAccent2))])),
                  const Spacer(),
                  const Icon(Icons.radar_rounded, size: 27, color: Color(0xFFB8B0FF)),
                ]),
                const SizedBox(height: 17),
                Text(_t('كل تفاصيل المنتج،\nفي صورة واحدة.', 'Product intelligence,\nfrom one photo.'), style: TextStyle(fontSize: 29, height: 1.18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 10),
                Text(_t('تعرّف على المنتج، قارن الأسعار، اكتشف المواصفات، وافحص مؤشرات الندرة من خلال تحليل الصورة والبحث على الويب.', 'Identify products, compare prices, explore specifications, and check rarity indicators using image analysis and web search.'), style: TextStyle(color: Color(0xFFD0D8EA), height: 1.65, fontSize: 13)),
                const SizedBox(height: 17),
                Wrap(spacing: 7, runSpacing: 7, children: [
                  _featurePill(Icons.price_check_rounded, 'مقارنة أسعار'),
                  _featurePill(Icons.travel_explore_rounded, 'بحث ويب'),
                  _featurePill(Icons.verified_outlined, 'فحص مؤشرات الأصالة'),
                  _featurePill(Icons.inventory_2_outlined, 'تقدير الندرة'),
                ]),
              ]),
            ),
            const SizedBox(height: 24),
            _sectionTitle(_t('1. صوّر أو ارفع المنتج', '1. Capture or upload a product'), _t('صورة واضحة للمنتج والملصق أو رقم الموديل تعطي نتيجة أدق.', 'A clear photo of the product, label, or model number improves accuracy.'), Icons.add_a_photo_outlined),
            InkWell(
              onTap: _imageOptions,
              borderRadius: BorderRadius.circular(22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                height: _image == null ? 212 : 275,
                decoration: BoxDecoration(
                  color: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _image == null ? const Color(0xFF34415E) : kAccent, width: 1.3),
                ),
                child: _image == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(width: 66, height: 66, decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(22)), child: const Icon(Icons.add_a_photo_rounded, size: 32, color: kAccent)),
                        const SizedBox(height: 14),
                        Text(_t('اضغط لاختيار صورة المنتج', 'Tap to select a product image'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 6),
                        Text(_t('الكاميرا أو معرض الصور • JPG / PNG / WebP', 'Camera or gallery • JPG / PNG / WebP'), style: TextStyle(color: kMuted, fontSize: 11)),
                      ])
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(21),
                        child: Stack(fit: StackFit.expand, children: [
                          GestureDetector(onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(backgroundColor: Colors.black, insetPadding: const EdgeInsets.all(12), child: InteractiveViewer(child: Image.file(_image!, fit: BoxFit.contain)))), child: Image.file(_image!, fit: BoxFit.contain)),
                          Positioned(top: 10, left: 10, child: IconButton.filled(onPressed: () => setState(() { _image = null; _result = ''; }), style: IconButton.styleFrom(backgroundColor: const Color(0xDD182237)), icon: const Icon(Icons.close_rounded), tooltip: 'إزالة الصورة')),
                          Positioned(right: 10, bottom: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: const Color(0xDD101827), borderRadius: BorderRadius.circular(30)), child: const Row(children: [Icon(Icons.zoom_in_rounded, size: 15, color: Colors.white), SizedBox(width: 4), Text('اضغط للتكبير', style: TextStyle(fontSize: 11))]))),
                        ]),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _chooseImage(ImageSource.camera), icon: const Icon(Icons.camera_alt_outlined), label: Text(_t('الكاميرا', 'Camera')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(47), side: const BorderSide(color: Color(0xFF34415E)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _chooseImage(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: Text(_t('المعرض', 'Gallery')), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(47), side: const BorderSide(color: Color(0xFF34415E)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
            ]),
            const SizedBox(height: 24),
            _sectionTitle(_t('2. خصّص البحث', '2. Customize your search'), _t('اختَر السوق ونوع المنتج وعمق التقرير للحصول على نتائج أقرب لاحتياجك.', 'Choose the market, product type, and report depth to tailor the results.'), Icons.tune_rounded),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel, borderRadius: BorderRadius.circular(22), border: Border.all(color: appThemeMode.value == ThemeMode.light ? const Color(0xFFE0E5EF) : const Color(0xFF202D45))),
              child: Column(children: [
                _dropdown(label: _t('السوق المستهدف', 'Target market'), value: _market, items: const ['مصر', 'السعودية', 'الإمارات', 'الكويت', 'قطر', 'الأردن', 'الولايات المتحدة', 'المملكة المتحدة', 'السوق العالمي'], icon: Icons.public_rounded, onChanged: (v) { if (v == null) return; setState(() => _market = v); _saveChoice('product_market', v); }),
                const SizedBox(height: 12),
                _dropdown(label: _t('تصنيف المنتج', 'Product category'), value: _category, items: const ['تلقائي', 'إلكترونيات', 'أجهزة منزلية', 'ملابس وأحذية', 'عطور ومستحضرات', 'ألعاب ومقتنيات', 'تحف وأنتيكات', 'كتب ومطبوعات', 'أدوات ومعدات', 'أخرى'], icon: Icons.category_outlined, onChanged: (v) { if (v == null) return; setState(() => _category = v); _saveChoice('product_category', v); }),
                const SizedBox(height: 12),
                _dropdown(label: _t('حالة المنتج للمقارنة', 'Product condition'), value: _condition, items: const ['غير محددة', 'جديد', 'مستعمل', 'مجدد / Refurbished', 'قطعة لهواة الاقتناء'], icon: Icons.inventory_2_outlined, onChanged: (v) { if (v == null) return; setState(() => _condition = v); _saveChoice('product_condition', v); }),
                const SizedBox(height: 12),
                _dropdown(label: _t('عمق التقرير', 'Report depth'), value: _detailLevel, items: const ['سريع', 'تفصيلي'], icon: Icons.subject_rounded, onChanged: (v) { if (v == null) return; setState(() => _detailLevel = v); _saveChoice('product_detail', v); }),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.travel_explore_rounded, color: kAccent2),
                  title: Text(_t('البحث عن الأسعار على الإنترنت', 'Search web for prices')),
                  subtitle: Text(_webSearchEnabled ? _t('مفعّل: سيستخدم طلب التحليل أداة البحث عن المصادر والأسعار الحديثة.', 'On: this analysis will use web search for current sources and prices.') : _t('مغلق لتوفير الاستهلاك. التحليل سيكون من الصورة والمعرفة المتاحة فقط.', 'Off to save usage. Analysis uses the image and model knowledge only.')),
                  value: _webSearchEnabled,
                  onChanged: (value) async {
                    setState(() => _webSearchEnabled = value);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('mango_web_search_enabled', value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _extraController,
                  maxLines: 3,
                  minLines: 2,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    labelText: _t('معلومات إضافية (اختياري)', 'Extra details (optional)'),
                    hintText: _t('مثال: أريد أقل سعر بالجنيه المصري، أو ابحث عن إصدار 2010، أو هذا المنتج مستعمل...', 'Example: find the lowest price, look for the 2010 edition, or treat it as used...'),
                    alignLabelWithHint: true,
                    prefixIcon: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.edit_note_rounded)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 19),
            _profitCalculator(),
            const SizedBox(height: 19),
            FilledButton.icon(
              onPressed: _busy ? null : _analyze,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(59),
                backgroundColor: const Color(0xFF8173F2),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF38334E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                elevation: 0,
              ),
              icon: _busy ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Icon(Icons.auto_awesome_rounded, size: 22),
              label: Text(_busy ? _t(_webSearchEnabled ? 'جاري تحليل الصورة والبحث على الويب…' : 'جاري تحليل صورة المنتج…', _webSearchEnabled ? 'Analyzing image and searching the web…' : 'Analyzing product image…') : _t(_webSearchEnabled ? 'حلّل المنتج وابحث عن أفضل سعر' : 'حلّل المنتج بدون بحث مباشر', _webSearchEnabled ? 'Analyze product & find the best price' : 'Analyze product without live search'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3, borderRadius: BorderRadius.all(Radius.circular(3)), color: kAccent2, backgroundColor: Color(0xFF1E2B40)),
              const SizedBox(height: 8),
              const Text('يقارن النموذج المعلومات المتاحة. قد يستغرق البحث بعض الوقت.', textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 11)),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon((_apiProvider == 'openai' ? _openAiKey.isNotEmpty : _apiKey.isNotEmpty) ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 18, color: (_apiProvider == 'openai' ? _openAiKey.isNotEmpty : _apiKey.isNotEmpty) ? kAccent2 : const Color(0xFFFFC477)),
                const SizedBox(width: 8),
                Expanded(child: Text((_apiProvider == 'openai' ? _openAiKey.isNotEmpty : _apiKey.isNotEmpty) ? _t('متصل • ${_apiProvider == 'openai' ? 'OpenAI' : 'Gemini'} • $_model', 'Connected • ${_apiProvider == 'openai' ? 'OpenAI' : 'Gemini'} • $_model') : _t('أضف مفتاح المزود المختار من الإعدادات لبدء التحليل', 'Add the selected provider key in Settings to begin'), style: const TextStyle(color: kMuted, fontSize: 11))),
                if ((_apiProvider == 'openai' ? _openAiKey.isEmpty : _apiKey.isEmpty)) TextButton(onPressed: _settings, child: Text(_t('إعداد', 'Settings'))), 
              ]),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: const Color(0xFF3A202C), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF693044))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFFFABB9)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFFD5DC), height: 1.55))),
                  IconButton(onPressed: () => setState(() => _error = null), icon: const Icon(Icons.close, size: 18), tooltip: _t('إغلاق', 'Close')),
                ]),
              ),
            ],
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 27),
              Container(
                key: _resultKey,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(color: appThemeMode.value == ThemeMode.light ? Colors.white : kPanel, borderRadius: BorderRadius.circular(23), border: Border.all(color: const Color(0xFF39466A)), boxShadow: const [BoxShadow(color: Color(0x17000000), blurRadius: 22, offset: Offset(0, 10))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 42, height: 42, decoration: BoxDecoration(color: kAccent2.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.fact_check_rounded, color: kAccent2)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_t('تقرير المنتج', 'Product report'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(_t('تم إنشاء التقرير بواسطة ${_apiProvider == 'openai' ? 'OpenAI' : 'Gemini'}', 'Report generated by ${_apiProvider == 'openai' ? 'OpenAI' : 'Gemini'}'), style: const TextStyle(color: kMuted, fontSize: 11))])),
                    IconButton(tooltip: 'نسخ التقرير', onPressed: () { Clipboard.setData(ClipboardData(text: _result)); _message('تم نسخ التقرير بالكامل'); }, icon: const Icon(Icons.copy_all_rounded)),
                  ]),
                  const SizedBox(height: 13),
                  const Divider(color: Color(0xFF2B3751)),
                  MarkdownBody(
                    data: _result,
                    selectable: true,
                    onTapLink: (text, href, title) { if (href != null) _openUrl(href); },
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 14, height: 1.78, color: Color(0xFFE4EAF7)),
                      h1: const TextStyle(fontSize: 22, height: 1.3, fontWeight: FontWeight.w900, color: Color(0xFFC2BBFF)),
                      h2: const TextStyle(fontSize: 18, height: 1.4, fontWeight: FontWeight.w800, color: Color(0xFFC2BBFF)),
                      h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF9FE9DE)),
                      a: const TextStyle(color: Color(0xFF87D6FF), decoration: TextDecoration.underline),
                      listBullet: const TextStyle(color: kAccent2),
                      blockquote: const TextStyle(color: kMuted, fontStyle: FontStyle.italic),
                      tableHead: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                      tableBody: const TextStyle(fontSize: 12, height: 1.5),
                      tableBorder: TableBorder.all(color: const Color(0xFF35415B), borderRadius: BorderRadius.circular(8)),
                      tableCellsPadding: const EdgeInsets.all(7),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF202A40), borderRadius: BorderRadius.circular(14)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_outlined, color: kAccent2, size: 19), SizedBox(width: 9), Expanded(child: Text('الأسعار والمخزون قد يتغيران، وتقرير الذكاء الاصطناعي ليس إثباتًا للأصالة أو تقييمًا رسميًا. افتح رابط المتجر وتحقق من الحالة والشحن قبل الشراء.', style: TextStyle(color: kMuted, fontSize: 11, height: 1.6)))])),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: _result)); _message('تم نسخ التقرير'); }, icon: const Icon(Icons.content_copy_rounded, size: 18), label: const Text('نسخ التقرير'), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))))),
                    const SizedBox(width: 9),
                    Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => _result = ''), icon: const Icon(Icons.close_rounded, size: 18), label: const Text('إخفاء التقرير'), style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))))),
                  ]),
                ]),
              ),
            ],
            const SizedBox(height: 27),
            Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFF111926), borderRadius: BorderRadius.circular(18)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.lock_outline_rounded, size: 19, color: kMuted), SizedBox(width: 10), Expanded(child: Text('صورك تُرسل إلى مزود الذكاء الاصطناعي الذي اخترته عند بدء التحليل. سجل التقارير محفوظ محليًا على جهازك. لا تحفظ بيانات حساسة في الصور، ولا تشارك مفاتيح API.', style: TextStyle(color: kMuted, fontSize: 11, height: 1.6)))])),
            const SizedBox(height: 14),
            Center(child: Text(_t('MANGO LENS • صناعة شركة مانجو • المؤسس مصطفى ماجد', 'MANGO LENS • Made by MANGO Company • Founder Mostafa Maged'), textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF697691), fontSize: 10, letterSpacing: 0.3))),
          ],
        ),
      ),
    );
  }
}