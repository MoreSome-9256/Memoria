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
#include <ncnn/gpu.h>
#include <ncnn/mat.h>
#include <ncnn/net.h>
#include "vendored_mobileclip_image_encoder.h"
#endif

namespace {

constexpr const char* kTag = "memoria_ncnn";
constexpr const char* kInputBlobName = "in0";
constexpr const char* kOutputBlobName = "out0";
constexpr int kExpectedInputLength = 3 * 256 * 256;
constexpr int kExpectedTextInputLength = 77;
constexpr int kExpectedOutputLength = 512;
constexpr int kEotTokenId = 49407;
std::mutex g_error_mutex;
std::mutex g_state_mutex;
std::string g_last_error = "NCNN backend not linked yet. FFI bridge is ready, but native inference is still stubbed.";
std::string g_param_path;
std::string g_bin_path;
std::string g_text_param_path;
std::string g_text_bin_path;
std::string g_projection_param_path;
std::string g_projection_bin_path;
bool g_model_init_requested = false;
bool g_text_model_init_requested = false;

#if MEMORIA_NCNN_RUNTIME_ENABLED
std::unique_ptr<VendoredMobileClipImageEncoder> g_mobileclip_encoder;
std::unique_ptr<ncnn::Net> g_text_encoder;
std::unique_ptr<ncnn::Net> g_projection_layer;
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

bool has_initialized_text_model_paths() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return g_text_model_init_requested &&
        !g_text_param_path.empty() &&
        !g_text_bin_path.empty() &&
        !g_projection_param_path.empty() &&
        !g_projection_bin_path.empty();
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

struct TextModelPaths {
    std::string text_param;
    std::string text_bin;
    std::string projection_param;
    std::string projection_bin;
};

TextModelPaths get_text_model_paths_copy() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return {
        g_text_param_path,
        g_text_bin_path,
        g_projection_param_path,
        g_projection_bin_path
    };
}

void clear_model_state_locked() {
    g_param_path.clear();
    g_bin_path.clear();
    g_text_param_path.clear();
    g_text_bin_path.clear();
    g_projection_param_path.clear();
    g_projection_bin_path.clear();
    g_model_init_requested = false;
    g_text_model_init_requested = false;
}

#if MEMORIA_NCNN_RUNTIME_ENABLED
bool has_loaded_runtime_model() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return g_mobileclip_encoder != nullptr;
}

bool has_loaded_runtime_text_model() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    return g_text_encoder != nullptr && g_projection_layer != nullptr;
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

int load_net(ncnn::Net& net, const std::string& param_path, const std::string& bin_path) {
    ncnn::create_gpu_instance();
    net.opt.use_vulkan_compute = ncnn::get_gpu_count() > 0;
    const int param_result = net.load_param(param_path.c_str());
    const int model_result = net.load_model(bin_path.c_str());
    return param_result == 0 && model_result == 0 ? 0 : -1;
}

int load_runtime_text_model_locked(const TextModelPaths& paths) {
    auto text_encoder = std::make_unique<ncnn::Net>();
    auto projection_layer = std::make_unique<ncnn::Net>();

    if (load_net(*text_encoder, paths.text_param, paths.text_bin) != 0) {
        set_last_error("Failed to load NCNN MobileCLIP text encoder .param/.bin files.");
        return -43;
    }
    if (load_net(*projection_layer, paths.projection_param, paths.projection_bin) != 0) {
        set_last_error("Failed to load NCNN MobileCLIP projection layer .param/.bin files.");
        return -44;
    }

    g_text_encoder = std::move(text_encoder);
    g_projection_layer = std::move(projection_layer);
    return 0;
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

std::string sibling_model_path(const char* source_path, const char* sibling_name) {
    std::filesystem::path path(source_path);
    return (path.parent_path() / sibling_name).string();
}

int eot_index_for_tokens(const int* token_ids, int token_len) {
    for (int i = 0; i < token_len; ++i) {
        if (token_ids[i] == kEotTokenId) {
            return i;
        }
    }
    return token_len > 0 ? token_len - 1 : 0;
}

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
    return (has_loaded_runtime_model() || has_loaded_runtime_text_model()) ? 1 : 0;
#else
    return 0;
#endif
}

int memoria_ncnn_release_model() {
    std::lock_guard<std::mutex> lock(g_state_mutex);
#if MEMORIA_NCNN_RUNTIME_ENABLED
    g_mobileclip_encoder.reset();
    g_text_encoder.reset();
    g_projection_layer.reset();
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
        } else if (g_text_encoder != nullptr && g_projection_layer != nullptr) {
            version = "ffi-bridge-ncnn-runtime-text";
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

int memoria_ncnn_init_image_model(const char* param_path, const char* bin_path) {
    return memoria_ncnn_init_model(param_path, bin_path);
}

int memoria_ncnn_init_text_model(const char* text_param_path, const char* text_bin_path) {
    if (text_param_path == nullptr || text_bin_path == nullptr) {
        set_last_error("NCNN text init received a null param/bin path.");
        return -1;
    }

    if (!file_exists(text_param_path)) {
        set_last_error("NCNN text init could not find the text .param file.");
        return -2;
    }
    if (!file_exists(text_bin_path)) {
        set_last_error("NCNN text init could not find the text .bin file.");
        return -3;
    }

    const std::string projection_param_path =
        sibling_model_path(text_param_path, "projection_layer.ncnn.param");
    const std::string projection_bin_path =
        sibling_model_path(text_param_path, "projection_layer.ncnn.bin");
    if (!file_exists(projection_param_path.c_str())) {
        set_last_error("NCNN text init could not find projection_layer.ncnn.param next to the text model.");
        return -4;
    }
    if (!file_exists(projection_bin_path.c_str())) {
        set_last_error("NCNN text init could not find projection_layer.ncnn.bin next to the text model.");
        return -5;
    }

    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        g_text_param_path = text_param_path;
        g_text_bin_path = text_bin_path;
        g_projection_param_path = projection_param_path;
        g_projection_bin_path = projection_bin_path;
        g_text_model_init_requested = true;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    {
        const TextModelPaths paths = get_text_model_paths_copy();
        std::lock_guard<std::mutex> lock(g_state_mutex);
        const int load_result = load_runtime_text_model_locked(paths);
        if (load_result != 0) {
            return load_result;
        }
    }

    set_last_error("NCNN text model initialized successfully.");
    return 0;
#else
    set_last_error(
        "NCNN text model files were staged successfully, but the native ncnn runtime is still not linked into this bridge."
    );
    return -6;
#endif
}

int memoria_ncnn_release_models() {
    return memoria_ncnn_release_model();
}

int memoria_ncnn_expected_image_input_length() {
    return memoria_ncnn_expected_input_length();
}

int memoria_ncnn_expected_text_input_length() {
    return kExpectedTextInputLength;
}

int memoria_ncnn_warmup_image() {
    return memoria_ncnn_warmup();
}

int memoria_ncnn_encode_text_tokens(
    const int* token_ids,
    int token_len,
    float* output,
    int output_len
);

int memoria_ncnn_warmup_text() {
    if (!has_initialized_text_model_paths()) {
        set_last_error(
            "NCNN text warmup was called before text model init. Stage text_encoder and projection_layer first."
        );
        return -2;
    }

    int tokens[kExpectedTextInputLength] = {};
    tokens[0] = 49406;
    tokens[1] = kEotTokenId;
    float output[kExpectedOutputLength] = {};
    return memoria_ncnn_encode_text_tokens(
        tokens,
        kExpectedTextInputLength,
        output,
        kExpectedOutputLength
    );
}

int memoria_ncnn_encode_text_tokens(
    const int* token_ids,
    int token_len,
    float* output,
    int output_len
) {
    if (token_ids == nullptr || output == nullptr) {
        set_last_error("Null token/output buffer passed to memoria_ncnn_encode_text_tokens.");
        return -1;
    }
    if (token_len != kExpectedTextInputLength) {
        set_last_error("Unexpected token length for NCNN text encoder. Expected 77 int32 tokens.");
        return -2;
    }
    if (output_len != kExpectedOutputLength) {
        set_last_error("Unexpected output length for NCNN text encoder. Expected 512 float32 output.");
        return -3;
    }
    if (!has_initialized_text_model_paths()) {
        set_last_error(
            "NCNN text encode was called before text model init. Stage text_encoder and projection_layer first."
        );
        return -5;
    }

#if MEMORIA_NCNN_RUNTIME_ENABLED
    auto paths = get_text_model_paths_copy();
    {
        std::lock_guard<std::mutex> lock(g_state_mutex);
        if (g_text_encoder == nullptr || g_projection_layer == nullptr) {
            const int load_result = load_runtime_text_model_locked(paths);
            if (load_result != 0) {
                return load_result;
            }
        }
    }

    ncnn::Mat token_mat(kExpectedTextInputLength, 1, (void*)token_ids, sizeof(int));
    auto text_ex = g_text_encoder->create_extractor();
    text_ex.set_light_mode(true);
    text_ex.input(kInputBlobName, token_mat.clone());

    ncnn::Mat text_out;
    if (text_ex.extract(kOutputBlobName, text_out) != 0 || text_out.empty()) {
        set_last_error("NCNN MobileCLIP text encoder failed during token inference.");
        return -31;
    }
    if (text_out.total() < static_cast<size_t>(kExpectedTextInputLength * kExpectedOutputLength)) {
        set_last_error("NCNN MobileCLIP text encoder returned an unexpected output shape.");
        return -32;
    }

    const int eot_index = eot_index_for_tokens(token_ids, token_len);
    std::vector<float> selected(kExpectedOutputLength);
    if (text_out.w == kExpectedOutputLength && text_out.h > eot_index) {
        const float* row = text_out.row(eot_index);
        std::copy(row, row + kExpectedOutputLength, selected.begin());
    } else {
        const float* text_values = text_out;
        const int offset = eot_index * kExpectedOutputLength;
        std::copy(text_values + offset, text_values + offset + kExpectedOutputLength, selected.begin());
    }

    ncnn::Mat projection_in(kExpectedOutputLength, 1, selected.data(), sizeof(float));
    auto projection_ex = g_projection_layer->create_extractor();
    projection_ex.set_light_mode(true);
    projection_ex.input(kInputBlobName, projection_in.clone());

    ncnn::Mat projection_out;
    if (projection_ex.extract(kOutputBlobName, projection_out) != 0 || projection_out.empty()) {
        set_last_error("NCNN MobileCLIP projection layer failed during text inference.");
        return -33;
    }
    if (projection_out.total() != static_cast<size_t>(kExpectedOutputLength)) {
        set_last_error("NCNN MobileCLIP projection layer returned an unexpected output size.");
        return -34;
    }

    const float* projected_values = projection_out;
    std::copy(projected_values, projected_values + kExpectedOutputLength, output);
    l2_normalize_inplace(output, output_len);
    set_last_error("NCNN text encode completed successfully.");
    return 0;
#else
    std::fill(output, output + output_len, 0.0f);
    set_last_error(
        "NCNN text encode stub was invoked after model staging. Link the real ncnn runtime before text inference."
    );
    return -4;
#endif
}

}
