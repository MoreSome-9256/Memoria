#include <algorithm>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <android/log.h>

#ifndef MEMORIA_NCNN_RUNTIME_ENABLED
#define MEMORIA_NCNN_RUNTIME_ENABLED 0
#endif

#if MEMORIA_NCNN_RUNTIME_ENABLED
#include <ncnn/mat.h>
#include <ncnn/net.h>
#include "vendored_mobileclip_image_encoder.h"
#endif

namespace {

constexpr const char* kTag = "memoria_ncnn";
constexpr const char* kInputBlobName = "in0";
constexpr const char* kOutputBlobName = "out0";
constexpr int kExpectedInputLength = 3 * 256 * 256;
constexpr int kExpectedOutputLength = 512;
std::mutex g_error_mutex;
std::mutex g_state_mutex;
std::string g_last_error = "NCNN backend not linked yet. FFI bridge is ready, but native inference is still stubbed.";
std::string g_param_path;
std::string g_bin_path;
bool g_model_init_requested = false;

#if MEMORIA_NCNN_RUNTIME_ENABLED
std::unique_ptr<VendoredMobileClipImageEncoder> g_mobileclip_encoder;
#endif

void set_last_error(const std::string& message) {
    std::lock_guard<std::mutex> lock(g_error_mutex);
    g_last_error = message;
    __android_log_print(ANDROID_LOG_WARN, kTag, "%s", g_last_error.c_str());
}

std::string get_last_error_copy() {
    std::lock_guard<std::mutex> lock(g_error_mutex);
    return g_last_error;
}

bool file_exists(const char* path) {
    if (path == nullptr || *path == '\0') {
        return false;
    }
    std::error_code error_code;
    return std::filesystem::exists(path, error_code);
}

bool has_initialized_model_paths() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return g_model_init_requested && !g_param_path.empty() && !g_bin_path.empty();
}

void copy_buffer(char* buffer, int buffer_len, const std::string& value) {
    const int bytes_to_copy = std::min<int>(buffer_len - 1, value.size());
    std::memcpy(buffer, value.data(), bytes_to_copy);
    buffer[bytes_to_copy] = '\0';
}

std::pair<std::string, std::string> get_model_paths_copy() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return {g_param_path, g_bin_path};
}

void clear_model_state_locked() {
    g_param_path.clear();
    g_bin_path.clear();
    g_model_init_requested = false;
}

#if MEMORIA_NCNN_RUNTIME_ENABLED
bool has_loaded_runtime_model() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return g_mobileclip_encoder != nullptr;
}

int load_runtime_model_locked(const std::string& param_path, const std::string& bin_path) {
    auto encoder = std::make_unique<VendoredMobileClipImageEncoder>(
        "mobileclip_s2",
        param_path,
        bin_path
    );
    if (!encoder->is_loaded()) {
        set_last_error("Failed to load author-provided NCNN image encoder .param/.bin files.");
        return -13;
    }
    g_mobileclip_encoder = std::move(encoder);
    return g_mobileclip_encoder != nullptr ? 0 : -12;
}

void l2_normalize_inplace(float* output, int output_len) {
    float squared_sum = 0.0f;
    for (int i = 0; i < output_len; ++i) {
        squared_sum += output[i] * output[i];
    }

    const float norm = std::sqrt(squared_sum);
    if (norm <= 0.0f) {
        return;
    }

    for (int i = 0; i < output_len; ++i) {
        output[i] /= norm;
    }
}

int copy_result_or_error(const std::vector<float>& values, float* output, int output_len) {
    if (static_cast<int>(values.size()) != output_len) {
        set_last_error("NCNN encode returned an unexpected embedding size. Inspect the exported .param/.bin graph.");
        return -34;
    }
    std::copy(values.begin(), values.end(), output);
    l2_normalize_inplace(output, output_len);
    set_last_error("NCNN encode completed successfully.");
    return 0;
}
#endif

}  // namespace

extern "C" {

int memoria_ncnn_init_model(const char* param_path, const char* bin_path) {
    if (param_path == nullptr || bin_path == nullptr) {
        set_last_error("NCNN init received a null param/bin path.");
        return -1;
    }

    if (!file_exists(param_path)) {
        set_last_error("NCNN init could not find the .param file at the provided path.");
        return -2;
    }

    if (!file_exists(bin_path)) {
        set_last_error("NCNN init could not find the .bin file at the provided path.");
        return -3;
    }

    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        g_param_path = param_path;
        g_bin_path = bin_path;
        g_model_init_requested = true;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        const int load_result = load_runtime_model_locked(g_param_path, g_bin_path);
        if (load_result != 0) {
            return load_result;
        }
    }

    set_last_error("NCNN model initialized successfully.");
    return 0;
#else
    set_last_error(
        "NCNN model files were staged successfully, but the native ncnn runtime is still not linked into this bridge."
    );
    return -4;
#endif
}

int memoria_ncnn_is_backend_available() {
#if MEMORIA_NCNN_RUNTIME_ENABLED
    return has_loaded_runtime_model() ? 1 : 0;
#else
    return 0;
#endif
}

int memoria_ncnn_release_model() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
#if MEMORIA_NCNN_RUNTIME_ENABLED
    g_mobileclip_encoder.reset();
#endif
    clear_model_state_locked();
    set_last_error("NCNN model released successfully.");
    return 0;
}

int memoria_ncnn_expected_input_length() {
    return kExpectedInputLength;
}

int memoria_ncnn_expected_output_length() {
    return kExpectedOutputLength;
}

int memoria_ncnn_get_version(char* buffer, int buffer_len) {
    if (buffer == nullptr || buffer_len <= 0) {
        return -1;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    std::string version = "ffi-bridge-runtime-uninitialized";
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_mobileclip_encoder != nullptr) {
            version = g_mobileclip_encoder->uses_vulkan()
                ? "ffi-bridge-ncnn-runtime-vulkan"
                : "ffi-bridge-ncnn-runtime-cpu";
        }
    }
#else
    const std::string version = has_initialized_model_paths()
        ? "ffi-bridge-init-ready"
        : "ffi-bridge-stub";
#endif
    copy_buffer(buffer, buffer_len, version);
    return std::min<int>(buffer_len - 1, version.size());
}

int memoria_ncnn_get_last_error(char* buffer, int buffer_len) {
    if (buffer == nullptr || buffer_len <= 0) {
        return -1;
    }

    const std::string message = get_last_error_copy();
    copy_buffer(buffer, buffer_len, message);
    return std::min<int>(buffer_len - 1, message.size());
}

int memoria_ncnn_warmup() {
    if (!has_initialized_model_paths()) {
        set_last_error(
            "NCNN warmup was called before model init. Stage the .param/.bin files and call memoria_ncnn_init_model first."
        );
        return -2;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    auto [param_path, bin_path] = get_model_paths_copy();
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_mobileclip_encoder == nullptr) {
            const int load_result = load_runtime_model_locked(param_path, bin_path);
            if (load_result != 0) {
                return load_result;
            }
        }
    }

    std::vector<unsigned char> zero_rgb(256 * 256 * 3, 0);
    std::vector<float> warmup_output;
    const int code = g_mobileclip_encoder->encode_rgb24(
        zero_rgb.data(),
        256,
        256,
        warmup_output
    );
    if (code != 0) {
        set_last_error("NCNN warmup failed inside vendored image encoder.");
        return -23;
    }
    return 0;
#else
    set_last_error(
        "NCNN backend is not available yet. Add the real ncnn model/runtime under the native bridge before warmup."
    );
    return -1;
#endif
}

int memoria_ncnn_encode_rgb24(
    const unsigned char* pixels,
    int width,
    int height,
    float* output,
    int output_len
) {
    if (pixels == nullptr || output == nullptr) {
        set_last_error("Null pixel/output buffer passed to memoria_ncnn_encode_rgb24.");
        return -1;
    }

    if (width <= 0 || height <= 0) {
        set_last_error("Invalid image size passed to memoria_ncnn_encode_rgb24.");
        return -2;
    }

    if (output_len != kExpectedOutputLength) {
        set_last_error("Unexpected output length for NCNN bridge. Expected 512 float32 output.");
        return -3;
    }

    if (!has_initialized_model_paths()) {
        set_last_error(
            "NCNN encode was called before model init. Stage the .param/.bin files and call memoria_ncnn_init_model first."
        );
        return -5;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    auto [param_path, bin_path] = get_model_paths_copy();
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_mobileclip_encoder == nullptr) {
            const int load_result = load_runtime_model_locked(param_path, bin_path);
            if (load_result != 0) {
                return load_result;
            }
        }
    }

    std::vector<float> values;
    const int code = g_mobileclip_encoder->encode_rgb24(
        pixels,
        width,
        height,
        values
    );
    if (code != 0) {
        set_last_error("Vendored MobileCLIP image encoder failed during RGB24 inference.");
        return -31;
    }
    return copy_result_or_error(values, output, output_len);
#else
    std::fill(output, output + output_len, 0.0f);
    set_last_error(
        "NCNN encode stub was invoked after model staging. Replace the stub implementation with the real ncnn extractor path."
    );
    return -4;
#endif
}

int memoria_ncnn_encode_rgba8888(
    const unsigned char* pixels,
    int width,
    int height,
    float* output,
    int output_len
) {
    if (pixels == nullptr || output == nullptr) {
        set_last_error("Null pixel/output buffer passed to memoria_ncnn_encode_rgba8888.");
        return -1;
    }

    if (width <= 0 || height <= 0) {
        set_last_error("Invalid image size passed to memoria_ncnn_encode_rgba8888.");
        return -2;
    }

    if (output_len != kExpectedOutputLength) {
        set_last_error("Unexpected output length for NCNN bridge. Expected 512 float32 output.");
        return -3;
    }

    if (!has_initialized_model_paths()) {
        set_last_error(
            "NCNN encode was called before model init. Stage the .param/.bin files and call memoria_ncnn_init_model first."
        );
        return -5;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    auto [param_path, bin_path] = get_model_paths_copy();
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_mobileclip_encoder == nullptr) {
            const int load_result = load_runtime_model_locked(param_path, bin_path);
            if (load_result != 0) {
                return load_result;
            }
        }
    }

    std::vector<float> values;
    const int code = g_mobileclip_encoder->encode_rgba8888(
        pixels,
        width,
        height,
        values
    );
    if (code != 0) {
        set_last_error("Vendored MobileCLIP image encoder failed during RGBA8888 inference.");
        return -31;
    }
    return copy_result_or_error(values, output, output_len);
#else
    std::fill(output, output + output_len, 0.0f);
    set_last_error(
        "NCNN encode stub was invoked after model staging. Replace the stub implementation with the real ncnn extractor path."
    );
    return -4;
#endif
}

int memoria_ncnn_encode_preprocessed_f32(
    const float* input,
    int input_len,
    float* output,
    int output_len
) {
    if (input == nullptr || output == nullptr) {
        set_last_error("Null input/output buffer passed to memoria_ncnn_encode_preprocessed_f32.");
        return -1;
    }

    if (input_len != kExpectedInputLength) {
        set_last_error(
            "Unexpected input length for NCNN bridge. Expected 3*256*256 float32 input."
        );
        return -2;
    }

    if (output_len != kExpectedOutputLength) {
        set_last_error("Unexpected output length for NCNN bridge. Expected 512 float32 output.");
        return -3;
    }

    if (!has_initialized_model_paths()) {
        set_last_error(
            "NCNN encode was called before model init. Stage the .param/.bin files and call memoria_ncnn_init_model first."
        );
        return -5;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    auto [param_path, bin_path] = get_model_paths_copy();
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_mobileclip_encoder == nullptr) {
            const int load_result = load_runtime_model_locked(param_path, bin_path);
            if (load_result != 0) {
                return load_result;
            }
        }
    }

    std::vector<float> values;
    const int code = g_mobileclip_encoder->encode_preprocessed_chw_f32(
        input,
        256,
        256,
        values
    );
    if (code != 0) {
        set_last_error("Vendored MobileCLIP image encoder failed during CHW float inference.");
        return -31;
    }
    return copy_result_or_error(values, output, output_len);
#else
    std::fill(output, output + output_len, 0.0f);
    set_last_error(
        "NCNN encode stub was invoked after model staging. Replace the stub implementation with the real ncnn extractor path."
    );
    return -4;
#endif
}

}
