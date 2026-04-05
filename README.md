# personal_health_diary

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Cloudflare Workers AI

The food scanner now sends local camera/gallery images to Cloudflare Workers AI for analysis.

Quick setup in this workspace:

1. Open `env/cloudflare.local.json`.
2. Fill:
	- `CLOUDFLARE_ACCOUNT_ID`
	- `CLOUDFLARE_API_TOKEN` (token permission: Workers AI Read or Workers AI Write)
3. In VS Code, run the launch profile: `Flutter (Workers AI)`.

An example template is provided at `env/cloudflare.local.example.json`.

Configure one of these options before running the app:

- `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` for direct access to `https://api.cloudflare.com/client/v4/accounts/<account>/ai/run/<model>`.
- `CLOUDFLARE_AI_ENDPOINT` if you want to point the app at a custom Worker or proxy that forwards the image to Workers AI.

Optional:

- `CLOUDFLARE_AI_MODEL` defaults to `@cf/llava-hf/llava-1.5-7b-hf`.

Example:

```bash
flutter run --dart-define=CLOUDFLARE_ACCOUNT_ID=your_account_id --dart-define=CLOUDFLARE_API_TOKEN=your_token
```
