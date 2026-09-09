#include "../RetroTrakk/Engine/SurgeBridge.h"
#include <cmath>
#include <cstdio>
#include <vector>

int main() {
    auto *surge = rtk_surge_create("Vendor/surge/resources/data", 44100.0);
    if (!surge) return 2;
    if (!rtk_surge_load_patch(surge, "Vendor/surge/resources/data/patches_factory/Basses/FM Bass 1.fxp")) return 3;
    rtk_surge_note_on(surge, 48, 110);
    std::vector<float> output(44100 * 2);
    rtk_surge_render(surge, output.data(), 44100);
    rtk_surge_note_off(surge, 48);
    float peak = 0;
    for (float sample : output) peak = std::max(peak, std::fabs(sample));
    rtk_surge_destroy(surge);
    std::printf("Surge embedded peak: %.6f\n", peak);
    return peak > 0.001f ? 0 : 4;
}
