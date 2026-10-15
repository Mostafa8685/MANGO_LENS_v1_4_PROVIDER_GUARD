# MANGO LENS — Product Intelligence v1.4

Arabic-first Flutter app by MANGO Company for identifying products from images, researching current prices when requested, and preparing seller-oriented reports.

## What's included in v1.4
- **Provider switch:** Google Gemini or OpenAI Responses API. Each provider has its own API key.
- **Editable model ID:** enter the exact model identifier in Settings; model names can change over time without changing app code. Gemini model discovery is available through the connection test.
- **Opt-in web search:** disabled by default to reduce usage. Turn on “Search web for prices” when you want current price comparisons. With it off, the prompt explicitly tells the model not to claim that prices or sources were checked live.
- **Usage guard:** blocks overlapping analyses, enforces a 15-second minimum gap between requests, persists the last-request time across restarts, and pauses requests for at least 90 seconds after an HTTP 429 (up to the provider's `Retry-After` value, capped at one hour). No automatic retries are made.
- **Local cache:** reuses the most recent report for the same image, provider, model, market, condition, category, detail level, web-search setting and extra instructions. Cached prices are clearly labelled as not freshly checked.
- **Lower token budget:** fast reports use up to 1,100 output tokens; detailed reports up to 2,400. Uploaded photos are resized and compressed by image_picker.
- Arabic/English interface, dark/light themes, scan history, report sharing/copying, and a local seller profit calculator.

## Configure and run
1. Install Flutter stable and Android tooling.
2. Run `flutter pub get`.
3. Run `flutter run`, or build with `flutter build apk --release`.
4. Open Settings, choose Gemini or OpenAI, enter that provider's API key, type a model ID, then save. Gemini's connection test can fetch model IDs; OpenAI's test checks the key via the models endpoint. Neither test generates an analysis.

## API key safety
Keys are stored locally on this device using SharedPreferences. That is suitable only for personal testing, not for a public commercial app. For MANGO LENS distribution to many users, put provider keys on a server-side proxy, authenticate users, and enforce per-user limits. Do not embed a shared company key in the APK.

## Important quota note
Client-side throttling and caching can reduce unnecessary requests but cannot increase provider quota or guarantee that HTTP 429 will never occur. Limits are enforced by each provider and may be model-, project-, account-, minute-, token-, or day-based. An API key test is not proof that generation quota is available.

## Build verification
This source archive has not been built with Flutter in this environment because the Flutter/Dart SDK is unavailable here. Use the included GitHub Actions workflow or run the build commands above to verify the APK.
