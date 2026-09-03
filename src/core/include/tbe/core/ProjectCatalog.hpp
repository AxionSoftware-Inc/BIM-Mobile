#pragma once

#include "tbe/core/Document.hpp"

namespace tbe::core {

// IDs returned by the one project-level catalog bootstrap.  IDs are document
// local; callers must never persist these values as global type identifiers.
struct DefaultProjectCatalog {
    ElementId concrete_material{};
    ElementId brick_material{};
    ElementId gypsum_material{};
    ElementId insulation_material{};
    ElementId screed_material{};
    ElementId laminate_material{};
    ElementId stair_tile_material{};
    ElementId glass_material{};
    ElementId aluminum_material{};
    ElementId asphalt_material{};
    ElementId paving_material{};
    ElementId grass_material{};
    ElementId timber_material{};

    ElementId exterior_wall_type{};
    ElementId interior_wall_type{};
    ElementId basic_wall_type{};
    ElementId exterior_glass_wall_type{};
    ElementId interior_glass_wall_type{};
    ElementId concrete_core_wall_type{};

    ElementId residential_floor_assembly{};
    ElementId asphalt_floor_assembly{};
    ElementId concrete_floor_assembly{};
    ElementId foundation_assembly{};
    ElementId showcase_foundation_assembly{};
    ElementId ceiling_assembly{};
    ElementId roof_assembly{};
    ElementId stair_assembly{};
    ElementId wood_floor_assembly{};
    ElementId paving_assembly{};
    ElementId grass_assembly{};
};

// Creates the shared starter catalog exactly once per document.  Existing
// records with the same semantic names are reused, which makes project repair
// and old template loading idempotent.
DefaultProjectCatalog ensure_default_project_catalog(Document& document);

// Read-only lookup used by template builders and API defaults. Missing records
// are returned as zero rather than silently creating a second catalog.
DefaultProjectCatalog find_default_project_catalog(const Document& document) noexcept;

} // namespace tbe::core
