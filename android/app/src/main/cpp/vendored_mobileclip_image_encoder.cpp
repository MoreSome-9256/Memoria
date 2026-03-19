#include "vendored_mobileclip_image_encoder.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace {

constexpr const char* kInputBlobName = "in0";
constexpr const char* kOutputBlobName = "out0";

void l2_normalize(std::vector<float>& values) {
    float squared_sum = 0.0f;
    for (const float value : values) {
        squared_sum += value * value;
    }

    const float norm = std::sqrt(squared_sum);
    if (norm <= 0.0f) {
        return;
    }

    for (float& value : values) {
        value /= norm;
    }
}

}  // namespace

VendoredMobileClipImageEncoder::VendoredMobileClipImageEncoder(
    const std::string& model_name,
    const std::string& param_path,
    const std::string& bin_path
) : model_name_(model_name) {
    const int param_result = image_encoder_.load_param(param_path.c_str());
    const int model_result = image_encoder_.load_model(bin_path.c_str());
    is_loaded_ = (param_result == 0 && model_result == 0);
}

bool VendoredMobileClipImageEncoder::is_loaded() const {
    return is_loaded_;
}

int VendoredMobileClipImageEncoder::target_size() const {
    return (model_name_ == "mobileclip_b" || model_name_ == "mobileclip_blt") ? 224 : 256;
}

int VendoredMobileClipImageEncoder::encode_rgb24(
    const unsigned char* pixels,
    int width,
    int height,
    std::vector<float>& output
) const {
    if (!is_loaded_ || pixels == nullptr || width <= 0 || height <= 0) {
        return -1;
    }

    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        pixels,
        ncnn::Mat::PIXEL_RGB,
        width,
        height,
        target_size(),
        target_size()
    );

    float mean_vals[3] = {0.0f, 0.0f, 0.0f};
    float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in.substract_mean_normalize(mean_vals, norm_vals);

    auto ex = image_encoder_.create_extractor();
    ex.set_light_mode(true);
    ex.input(kInputBlobName, in);

    ncnn::Mat out0;
    ex.extract(kOutputBlobName, out0);

    const int flat_length = out0.w * std::max(1, out0.h) * std::max(1, out0.c);
    output.resize(flat_length);
    std::memcpy(output.data(), out0.data, flat_length * sizeof(float));
    l2_normalize(output);
    return 0;
}

int VendoredMobileClipImageEncoder::encode_rgba8888(
    const unsigned char* pixels,
    int width,
    int height,
    std::vector<float>& output
) const {
    if (!is_loaded_ || pixels == nullptr || width <= 0 || height <= 0) {
        return -1;
    }

    ncnn::Mat in = ncnn::Mat::from_pixels_resize(
        pixels,
        ncnn::Mat::PIXEL_RGBA2RGB,
        width,
        height,
        target_size(),
        target_size()
    );

    float mean_vals[3] = {0.0f, 0.0f, 0.0f};
    float norm_vals[3] = {1.0f / 255.0f, 1.0f / 255.0f, 1.0f / 255.0f};
    in.substract_mean_normalize(mean_vals, norm_vals);

    auto ex = image_encoder_.create_extractor();
    ex.set_light_mode(true);
    ex.input(kInputBlobName, in);

    ncnn::Mat out0;
    ex.extract(kOutputBlobName, out0);

    const int flat_length = out0.w * std::max(1, out0.h) * std::max(1, out0.c);
    output.resize(flat_length);
    std::memcpy(output.data(), out0.data, flat_length * sizeof(float));
    l2_normalize(output);
    return 0;
}

int VendoredMobileClipImageEncoder::encode_preprocessed_chw_f32(
    const float* chw_input,
    int width,
    int height,
    std::vector<float>& output
) const {
    if (!is_loaded_ || chw_input == nullptr || width <= 0 || height <= 0) {
        return -1;
    }

    ncnn::Mat in(width, height, 3);
    const int channel_area = width * height;
    for (int channel = 0; channel < 3; ++channel) {
        std::memcpy(
            in.channel(channel),
            chw_input + channel * channel_area,
            channel_area * sizeof(float)
        );
    }

    auto ex = image_encoder_.create_extractor();
    ex.set_light_mode(true);
    ex.input(kInputBlobName, in);

    ncnn::Mat out0;
    ex.extract(kOutputBlobName, out0);

    const int flat_length = out0.w * std::max(1, out0.h) * std::max(1, out0.c);
    output.resize(flat_length);
    std::memcpy(output.data(), out0.data, flat_length * sizeof(float));
    l2_normalize(output);
    return 0;
}