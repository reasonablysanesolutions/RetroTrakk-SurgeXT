#include "SurgeBridge.h"

#include "SurgeSynthesizer.h"
#include <algorithm>
#include <memory>

namespace {
class Host final : public SurgeSynthesizer::PluginLayer {
  public:
    void surgeParameterUpdated(const SurgeSynthesizer::ID &, float) override {}
    void surgeMacroUpdated(long, float) override {}
};
}

struct RTKSurge {
    Host host;
    std::unique_ptr<SurgeSynthesizer> synth;
    int blockOffset = 0;
};

RTKSurge *rtk_surge_create(const char *data_path, double sample_rate) {
    try {
        auto result = std::make_unique<RTKSurge>();
        // RetroTrakk loads a known, bundled factory patch by absolute path.  The
        // host-facing Surge browser catalogue is therefore unnecessary here and
        // would scan the user's global wavetable folders on the UI thread.
        SurgeStorage::skipLoadWtAndPatch = true;
        SurgeStorage::skipUserPresetScans = true;
        result->synth = std::make_unique<SurgeSynthesizer>(&result->host, data_path ? data_path : "");
        SurgeStorage::skipLoadWtAndPatch = false;
        SurgeStorage::skipUserPresetScans = false;
        result->synth->setSamplerate(static_cast<float>(sample_rate));
        result->synth->time_data.tempo = 125.0;
        return result.release();
    } catch (...) {
        SurgeStorage::skipLoadWtAndPatch = false;
        SurgeStorage::skipUserPresetScans = false;
        return nullptr;
    }
}

void rtk_surge_destroy(RTKSurge *surge) { delete surge; }

int rtk_surge_load_patch(RTKSurge *surge, const char *patch_path) {
    if (!surge || !patch_path) return 0;
    return surge->synth->loadPatchByPath(patch_path, -1, "RetroTrakk", true) ? 1 : 0;
}

void rtk_surge_note_on(RTKSurge *surge, unsigned char note, unsigned char velocity) {
    if (surge) surge->synth->playNote(0, static_cast<char>(note), static_cast<char>(velocity), 0, note);
}

void rtk_surge_note_off(RTKSurge *surge, unsigned char note) {
    if (surge) surge->synth->releaseNote(0, static_cast<char>(note), 0, note);
}

void rtk_surge_all_notes_off(RTKSurge *surge) {
    if (surge) surge->synth->allNotesOff();
}

void rtk_surge_render(RTKSurge *surge, float *out, int frames) {
    if (!out || frames <= 0) return;
    if (!surge) {
        std::fill(out, out + frames * 2, 0.0f);
        return;
    }
    for (int frame = 0; frame < frames; ++frame) {
        if (surge->blockOffset == 0) surge->synth->process();
        out[frame * 2] = surge->synth->output[0][surge->blockOffset];
        out[frame * 2 + 1] = surge->synth->output[1][surge->blockOffset];
        surge->blockOffset = (surge->blockOffset + 1) % surge->synth->getBlockSize();
    }
}
