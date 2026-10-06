#ifndef AT_NATIVE_H
#define AT_NATIVE_H

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
  #define AT_API __declspec(dllexport)
#else
  #define AT_API
#endif

// Request structure passed from Lua
typedef struct {
    const char* request_id;
    const char* text;
    const char* target_lang;     // "ja" or "en"
    const char* primary_provider; // "deepl", "openai", "claude"
    const char* deepl_key;
    const char* openai_key;
    const char* claude_key;
    const char* glossary_json;   // e.g. "{"hello":"こんにちは","lfg":"Party LFG"}"
} AT_Request;

// Result structure polled by Lua
typedef struct {
    char request_id[64];
    char translated_text[2048];
    char provider_used[32];
    int success; // 1 = ok, 0 = error
    char error_msg[256];
} AT_Result;

// Exported C-API functions
AT_API void AT_Init();
AT_API void AT_Shutdown();
AT_API int AT_TranslateAsync(
    const char* req_id,
    const char* text,
    const char* target_lang,
    const char* primary_provider,
    const char* deepl_key,
    const char* openai_key,
    const char* claude_key,
    const char* glossary_json
);
AT_API int AT_PollResult(AT_Result* out_result);

#ifdef __cplusplus
}
#endif

#endif // AT_NATIVE_H
