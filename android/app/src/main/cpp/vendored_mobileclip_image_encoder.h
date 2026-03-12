#pragma once

#include <string>
#include <vector>

#include <ncnn/mat.h>
#include <ncnn/net.h>

class VendoredMobileClipImageEncoder {
public:
    VendoredMobileClipImageEncoder(
        const std::string& model_name,
        const std::string& param_path,
        const std::string& bin_path
    );

    bool is_loaded() const;

    int encode_rgb24(
        const unsigned char* pixels,
        int width,
        int height,
        std::vector<float>& output
    ) const;

    int encode_rgba8888(
        const unsigned char* pixels,
        int width,
        int height,
        std::vector<float>& output
    ) const;

    int encode_preprocessed_chw_f32(
        const float* chw_input,
        int width,
        int height,
        std::vector<float>& output
    ) const;

private:
    int target_size() const;

    ncnn::Net image_encoder_;
    std::string model_name_;
    bool is_loaded_ = false;
};