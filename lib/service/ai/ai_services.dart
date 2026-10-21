import 'package:anx_reader/utils/env_var.dart';

class AiServiceOption {
  const AiServiceOption({
    required this.identifier,
    required this.title,
    required this.defaultUrl,
    required this.defaultApiKey,
    required this.defaultModel,
    this.logo,
  });

  final String identifier;
  final String title;
  // Asset path for built-in providers; null renders a letter avatar.
  final String? logo;
  final String defaultUrl;
  final String defaultApiKey;
  final String defaultModel;
}

List<AiServiceOption> buildDefaultAiServices() {
  return [
    !EnvVar.enableOpenAiConfig
        ? AiServiceOption(
            identifier: 'openai',
            title: '通用',
            logo: 'assets/images/commonAi.png',
            defaultUrl:
                'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
            defaultApiKey: 'YOUR_API_KEY',
            defaultModel: 'qwen-long',
          )
        : AiServiceOption(
            identifier: 'openai',
            title: 'OpenAI',
            logo: 'assets/images/openai.png',
            defaultUrl: 'https://api.openai.com/v1/chat/completions',
            defaultApiKey: 'YOUR_API_KEY',
            defaultModel: 'gpt-4o-mini',
          ),
    AiServiceOption(
      identifier: 'claude',
      title: 'Claude',
      logo: 'assets/images/claude.png',
      defaultUrl: 'https://api.anthropic.com/v1/messages',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'claude-3-5-sonnet-20240620',
    ),
    AiServiceOption(
      identifier: 'gemini',
      title: 'Gemini',
      logo: 'assets/images/gemini.png',
      defaultUrl: 'https://generativelanguage.googleapis.com',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'gemini-2.5-flash',
    ),
    AiServiceOption(
      identifier: 'deepseek',
      title: 'DeepSeek',
      logo: 'assets/images/deepseek.png',
      defaultUrl: 'https://api.deepseek.com/v1/chat/completions',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'deepseek-chat',
    ),
    AiServiceOption(
      identifier: 'openrouter',
      title: 'OpenRouter',
      logo: 'assets/images/openrouter.png',
      defaultUrl: 'https://openrouter.ai/api/v1/chat/completions',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'gpt-4o-mini',
    ),
    AiServiceOption(
      identifier: 'requesty',
      title: 'Requesty',
      logo: 'assets/images/requesty.png',
      defaultUrl: 'https://router.requesty.ai/v1/chat/completions',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'openai/gpt-4o-mini',
    ),
    // Local inference servers — OpenAI-compatible endpoints, no API key needed.
    AiServiceOption(
      identifier: 'ollama',
      title: 'Ollama (本地)',
      defaultUrl: 'http://127.0.0.1:11434/v1',
      defaultApiKey: '',
      defaultModel: 'qwen3:4b',
    ),
    AiServiceOption(
      identifier: 'lmstudio',
      title: 'LM Studio (本地)',
      defaultUrl: 'http://127.0.0.1:1234/v1',
      defaultApiKey: '',
      // LM Studio has no stable default model id — pick one after loading
      // a model in LM Studio, or use "获取模型列表".
      defaultModel: '',
    ),
    AiServiceOption(
      identifier: 'llamacpp',
      title: 'llama.cpp (本地)',
      defaultUrl: 'http://127.0.0.1:8080/v1',
      defaultApiKey: '',
      // Depends on the model loaded by `llama-server`; fetch via /v1/models.
      defaultModel: '',
    ),
  ];
}
