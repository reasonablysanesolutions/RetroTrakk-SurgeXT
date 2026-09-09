#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RTKSurge RTKSurge;

RTKSurge *rtk_surge_create(const char *data_path, double sample_rate);
void rtk_surge_destroy(RTKSurge *surge);
int rtk_surge_load_patch(RTKSurge *surge, const char *patch_path);
void rtk_surge_note_on(RTKSurge *surge, unsigned char note, unsigned char velocity);
void rtk_surge_note_off(RTKSurge *surge, unsigned char note);
void rtk_surge_all_notes_off(RTKSurge *surge);
void rtk_surge_render(RTKSurge *surge, float *interleaved_stereo, int frame_count);

#ifdef __cplusplus
}
#endif
