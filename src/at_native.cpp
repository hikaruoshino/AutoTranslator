#include "at_native.h"
#include <windows.h>
#include <winhttp.h>
#include <string>
#include <thread>
#include <mutex>
#include <queue>
#include <vector>
#include <sstream>

#pragma comment(lib, "winhttp.lib")

// Thread-safe result queue
static std::queue<AT_Result> g_resultQueue;
static std::mutex g_queueMutex;
static bool g_initialized = false;

// Helper: Convert UTF-8 std::string to std::wstring
static std::wstring Utf8ToWide(const std::string& str) {
    if (str.empty()) return L"";
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), (int)str.size(), NULL, 0);
    std::wstring wstr(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), (int)str.size(), &wstr[0], size_needed);
    return wstr;
}

// Helper: Convert std::wstring to UTF-8 std::string
static std::string WideToUtf8(const std::wstring& wstr) {
    if (wstr.empty()) return "";
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), NULL, 0, NULL, NULL);
    std::string str(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), (int)wstr.size(), &str[0], size_needed, NULL, NULL);
    return str;
}

// Helper: Escape string for JSON
static std::string JsonEscape(const std::string& s) {
    std::ostringstream o;
    for (char c : s) {
        if (c == '"') o << "\\\"";
        else if (c == '\\') o << "\\\\";
        else if (c == '\b') o << "\\b";
        else if (c == '\f') o << "\\f";
        else if (c == '\n') o << "\\n";
        else if (c == '\r') o << "\\r";
        else if (c == '\t') o << "\\t";
        else o << c;
    }
    return o.str();
}

// Helper: Perform HTTPS POST via WinHTTP
static bool HttpPost(
    const std::wstring& host,
    INTERNET_PORT port,
    const std::wstring& path,
    const std::vector<std::wstring>& headers,
    const std::string& body,
    std::string& out_response,
    int& out_http_code
) {
    HINTERNET hSession = WinHttpOpen(
        L"AutoTranslatorNative/3.0 (Win32)",
        WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS, 0
    );
    if (!hSession) return false;

    // Set timeout (3 seconds max per provider)
    WinHttpSetTimeouts(hSession, 3000, 3000, 3000, 3000);

    HINTERNET hConnect = WinHttpConnect(hSession, host.c_str(), port, 0);
    if (!hConnect) {
        WinHttpCloseHandle(hSession);
        return false;
    }

    DWORD flags = WINHTTP_FLAG_SECURE; // HTTPS
    HINTERNET hRequest = WinHttpOpenRequest(
        hConnect, L"POST", path.c_str(),
        NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags
    );
    if (!hRequest) {
        WinHttpCloseHandle(hConnect);
        WinHttpCloseHandle(hSession);
        return false;
    }

    // Add Headers
    for (const auto& h : headers) {
        WinHttpAddRequestHeaders(hRequest, h.c_str(), (DWORD)-1L, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
    }

    // Send Request
    BOOL bResults = WinHttpSendRequest(
        hRequest,
        WINHTTP_NO_ADDITIONAL_HEADERS, 0,
        (LPVOID)body.c_str(), (DWORD)body.length(),
        (DWORD)body.length(), 0
    );

    if (bResults) {
        bResults = WinHttpReceiveResponse(hRequest, NULL);
    }

    if (bResults) {
        DWORD dwStatusCode = 0;
        DWORD dwSize = sizeof(dwStatusCode);
        WinHttpQueryHeaders(
            hRequest,
            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
            WINHTTP_HEADER_NAME_BY_INDEX,
            &dwStatusCode, &dwSize, WINHTTP_NO_HEADER_INDEX
        );
        out_http_code = (int)dwStatusCode;

        // Read Response Body
        DWORD dwDownloaded = 0;
        std::vector<char> buffer;
        do {
            DWORD dwSizeRead = 0;
            if (!WinHttpQueryDataAvailable(hRequest, &dwSizeRead)) break;
            if (dwSizeRead == 0) break;

            size_t oldSize = buffer.size();
            buffer.resize(oldSize + dwSizeRead);
            if (!WinHttpReadData(hRequest, &buffer[oldSize], dwSizeRead, &dwDownloaded)) break;
        } while (dwDownloaded > 0);

        out_response = std::string(buffer.begin(), buffer.end());
    }

    WinHttpCloseHandle(hRequest);
    WinHttpCloseHandle(hConnect);
    WinHttpCloseHandle(hSession);
    return bResults ? true : false;
}

// Simple JSON extraction helpers
static std::string ExtractJsonField(const std::string& json, const std::string& key) {
    size_t pos = json.find("\"" + key + "\"");
    if (pos == std::string::npos) return "";
    pos = json.find(":", pos);
    if (pos == std::string::npos) return "";
    pos = json.find("\"", pos);
    if (pos == std::string::npos) return "";

    size_t start = pos + 1;
    size_t end = start;
    bool escaped = false;
    while (end < json.length()) {
        if (json[end] == '\\' && !escaped) {
            escaped = true;
        } else if (json[end] == '"' && !escaped) {
            break;
        } else {
            escaped = false;
        }
        end++;
    }
    return json.substr(start, end - start);
}

// Provider execution logic
static bool ExecuteDeepL(const std::string& text, const std::string& key, const std::string& target_lang, std::string& out_text, std::string& out_err) {
    if (key.empty() || key.find("YOUR_") != std::string::npos) {
        out_err = "DeepL Key Missing";
        return false;
    }
    bool is_free = (key.length() > 3 && key.substr(key.length() - 3) == ":fx");
    std::wstring host = is_free ? L"api-free.deepl.com" : L"api.deepl.com";
    std::wstring path = L"/v2/translate";

    std::vector<std::wstring> headers;
    headers.push_back(L"Content-Type: application/json");
    headers.push_back(L"Authorization: DeepL-Auth-Key " + Utf8ToWide(key));

    std::string body = "{\"text\":[\"" + JsonEscape(text) + "\"],\"target_lang\":\"" + (target_lang == "en" ? "EN" : "JA") + "\"}";

    std::string resp;
    int status = 0;
    if (HttpPost(host, INTERNET_DEFAULT_HTTPS_PORT, path, headers, body, resp, status) && status == 200) {
        std::string trans = ExtractJsonField(resp, "text");
        if (!trans.empty()) {
            out_text = trans;
            return true;
        }
    }
    out_err = "DeepL Error (HTTP " + std::to_string(status) + ")";
    return false;
}

static bool ExecuteOpenAI(const std::string& text, const std::string& key, const std::string& target_lang, std::string& out_text, std::string& out_err) {
    if (key.empty() || key.find("YOUR_") != std::string::npos) {
        out_err = "OpenAI Key Missing";
        return false;
    }
    std::wstring host = L"api.openai.com";
    std::wstring path = L"/v1/chat/completions";

    std::vector<std::wstring> headers;
    headers.push_back(L"Content-Type: application/json");
    headers.push_back(L"Authorization: Bearer " + Utf8ToWide(key));

    std::string sys_prompt = "You are an expert FFXI chat translator. Translate into " + (target_lang == "en" ? std::string("natural English") : std::string("natural Japanese")) + ". Output ONLY translated text without extra commentary.";
    std::string body = "{\"model\":\"gpt-4o-mini\",\"messages\":[{\"role\":\"system\",\"content\":\"" + JsonEscape(sys_prompt) + "\"},{\"role\":\"user\",\"content\":\"" + JsonEscape(text) + "\"}],\"temperature\":0.0}";

    std::string resp;
    int status = 0;
    if (HttpPost(host, INTERNET_DEFAULT_HTTPS_PORT, path, headers, body, resp, status) && status == 200) {
        std::string content = ExtractJsonField(resp, "content");
        if (!content.empty()) {
            out_text = content;
            return true;
        }
    }
    out_err = "OpenAI Error (HTTP " + std::to_string(status) + ")";
    return false;
}

static bool ExecuteClaude(const std::string& text, const std::string& key, const std::string& target_lang, std::string& out_text, std::string& out_err) {
    if (key.empty() || key.find("YOUR_") != std::string::npos) {
        out_err = "Claude Key Missing";
        return false;
    }
    std::wstring host = L"api.anthropic.com";
    std::wstring path = L"/v1/messages";

    std::vector<std::wstring> headers;
    headers.push_back(L"Content-Type: application/json");
    headers.push_back(L"x-api-key: " + Utf8ToWide(key));
    headers.push_back(L"anthropic-version: 2023-06-01");

    std::string sys_prompt = "You are an expert FFXI chat translator. Translate into " + (target_lang == "en" ? std::string("natural English") : std::string("natural Japanese")) + ". Output ONLY translated text.";
    std::string body = "{\"model\":\"claude-3-haiku-20240307\",\"system\":\"" + JsonEscape(sys_prompt) + "\",\"messages\":[{\"role\":\"user\",\"content\":\"" + JsonEscape(text) + "\"}],\"max_tokens\":60}";

    std::string resp;
    int status = 0;
    if (HttpPost(host, INTERNET_DEFAULT_HTTPS_PORT, path, headers, body, resp, status) && status == 200) {
        std::string text_field = ExtractJsonField(resp, "text");
        if (!text_field.empty()) {
            out_text = text_field;
            return true;
        }
    }
    out_err = "Claude Error (HTTP " + std::to_string(status) + ")";
    return false;
}

// Background Worker Thread
static void WorkerThread(
    std::string req_id,
    std::string text,
    std::string target_lang,
    std::string primary_provider,
    std::string deepl_key,
    std::string openai_key,
    std::string claude_key
) {
    AT_Result res;
    memset(&res, 0, sizeof(res));
    strncpy(res.request_id, req_id.c_str(), sizeof(res.request_id) - 1);

    std::vector<std::string> providers;
    if (primary_provider == "openai") {
        providers = {"openai", "deepl", "claude"};
    } else if (primary_provider == "claude") {
        providers = {"claude", "deepl", "openai"};
    } else {
        providers = {"deepl", "openai", "claude"}; // Default DeepL first
    }

    std::string translated;
    std::string last_error;
    bool success = false;
    std::string used_provider;

    for (const auto& p : providers) {
        std::string err;
        if (p == "deepl") {
            if (ExecuteDeepL(text, deepl_key, target_lang, translated, err)) {
                success = true; used_provider = "DeepL"; break;
            } else { last_error = err; }
        } else if (p == "openai") {
            if (ExecuteOpenAI(text, openai_key, target_lang, translated, err)) {
                success = true; used_provider = "OpenAI"; break;
            } else { last_error = err; }
        } else if (p == "claude") {
            if (ExecuteClaude(text, claude_key, target_lang, translated, err)) {
                success = true; used_provider = "Claude"; break;
            } else { last_error = err; }
        }
    }

    if (success) {
        res.success = 1;
        strncpy(res.translated_text, translated.c_str(), sizeof(res.translated_text) - 1);
        strncpy(res.provider_used, used_provider.c_str(), sizeof(res.provider_used) - 1);
    } else {
        res.success = 0;
        strncpy(res.error_msg, last_error.c_str(), sizeof(res.error_msg) - 1);
    }

    // Push to thread-safe queue
    std::lock_guard<std::mutex> lock(g_queueMutex);
    g_resultQueue.push(res);
}

// C-API Implementation
extern "C" {

AT_API void AT_Init() {
    g_initialized = true;
}

AT_API void AT_Shutdown() {
    std::lock_guard<std::mutex> lock(g_queueMutex);
    while (!g_resultQueue.empty()) g_resultQueue.pop();
    g_initialized = false;
}

AT_API int AT_TranslateAsync(
    const char* req_id,
    const char* text,
    const char* target_lang,
    const char* primary_provider,
    const char* deepl_key,
    const char* openai_key,
    const char* claude_key,
    const char* glossary_json
) {
    if (!text || strlen(text) == 0) return 0;

    std::thread worker(
        WorkerThread,
        req_id ? std::string(req_id) : "0",
        std::string(text),
        target_lang ? std::string(target_lang) : "ja",
        primary_provider ? std::string(primary_provider) : "deepl",
        deepl_key ? std::string(deepl_key) : "",
        openai_key ? std::string(openai_key) : "",
        claude_key ? std::string(claude_key) : ""
    );
    worker.detach(); // Fire and forget in native background thread!
    return 1;
}

AT_API int AT_PollResult(AT_Result* out_result) {
    if (!out_result) return 0;

    std::lock_guard<std::mutex> lock(g_queueMutex);
    if (g_resultQueue.empty()) {
        return 0; // No results pending
    }

    *out_result = g_resultQueue.front();
    g_resultQueue.pop();
    return 1; // Result retrieved
}

} // extern "C"
