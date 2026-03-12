#include <fstream>
#include <iomanip>
#include <stdexcept>
#include <string>

#include <ncnn/mat.h>

namespace mobileclip_dump {

void dump_embedding_text(const ncnn::Mat& out_embed, const std::string& output_path) {
    if (out_embed.total() != 512) {
        throw std::runtime_error("Expected a 512-d embedding before dumping text output.");
    }

    const float* ptr = static_cast<const float*>(out_embed.data);
    std::ofstream out_file(output_path, std::ios::out | std::ios::trunc);
    if (!out_file.is_open()) {
        throw std::runtime_error("Failed to open text output file: " + output_path);
    }

    out_file << std::fixed << std::setprecision(8);
    for (int index = 0; index < 512; ++index) {
        out_file << ptr[index];
        if (index + 1 < 512) {
            out_file << '\n';
        }
    }
}

void dump_embedding_bin(const ncnn::Mat& out_embed, const std::string& output_path) {
    if (out_embed.total() != 512) {
        throw std::runtime_error("Expected a 512-d embedding before dumping binary output.");
    }

    const float* ptr = static_cast<const float*>(out_embed.data);
    std::ofstream out_file(output_path, std::ios::out | std::ios::binary | std::ios::trunc);
    if (!out_file.is_open()) {
        throw std::runtime_error("Failed to open binary output file: " + output_path);
    }

    out_file.write(reinterpret_cast<const char*>(ptr), sizeof(float) * 512);
}

}  // namespace mobileclip_dump