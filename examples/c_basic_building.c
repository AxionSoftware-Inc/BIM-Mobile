#include "tbe/api/EngineCApi.h"

#include <stdio.h>
#include <string.h>

int main(void) {
    TbeEngineHandle* handle = tbe_engine_create();
    if (handle == NULL) {
        return 1;
    }

    unsigned long long wall_a = 0;
    unsigned long long wall_b = 0;
    unsigned long long wall_c = 0;
    unsigned long long wall_d = 0;
    unsigned long long room_count = 0;
    TbeScheduleSummary schedule = {0};
    TbeValidationSummary validation = {0};
    char* json = NULL;

    tbe_create_wall(handle, "A", 0, (TbeVec2){0.0, 0.0}, (TbeVec2){4.0, 0.0}, 0.2, 3.0, &wall_a);
    tbe_create_wall(handle, "B", 0, (TbeVec2){4.0, 0.0}, (TbeVec2){4.0, 3.0}, 0.2, 3.0, &wall_b);
    tbe_create_wall(handle, "C", 0, (TbeVec2){4.0, 3.0}, (TbeVec2){0.0, 3.0}, 0.2, 3.0, &wall_c);
    tbe_create_wall(handle, "D", 0, (TbeVec2){0.0, 3.0}, (TbeVec2){0.0, 0.0}, 0.2, 3.0, &wall_d);
    tbe_create_door(handle, "Door", wall_a, 1.0, 0.9, 2.1, &wall_c);
    tbe_create_window(handle, "Window", wall_b, 1.5, 1.0, 1.2, 1.0, &wall_d);
    tbe_detect_rooms(handle, &room_count);
    tbe_generate_schedules(handle, &schedule);
    tbe_validate(handle, &validation);
    tbe_project_save_json(handle, &json);
    tbe_export_project_package(handle, "./c_basic_building_package");

    printf("room_count=%llu\n", room_count);
    printf("wall_rows=%zu\n", schedule.wall_rows);
    printf("validation_errors=%d\n", validation.error_count);
    printf("json_size=%zu\n", json != NULL ? (size_t)strlen(json) : 0U);

    tbe_free_string(json);
    tbe_engine_destroy(handle);
    return validation.error_count == 0 ? 0 : 1;
}
