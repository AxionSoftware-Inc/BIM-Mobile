#pragma once

#include "tbe/core/Document.hpp"

#include <filesystem>
#include <string>
#include <vector>

namespace tbe::core {

struct IfcExchangeReport {
    std::size_t exported_elements{};
    std::size_t imported_elements{};
    std::vector<std::string> warnings{};
};

/// Writes an IFC4 STEP document containing standard semantic entities. The
/// TBE semantic sidecar is stored as an IFC comment so authored dimensions,
/// relations and typed metadata survive a lossless Tablet BIM round-trip.
void export_ifc(const Document& document, const std::filesystem::path& path, IfcExchangeReport* report = nullptr);

/// Imports a Tablet BIM IFC export losslessly. Third-party IFC files use the
/// native STEP geometry path for faceted BREP, mapped BREP and common extruded
/// profiles; products whose representation is still outside that path retain
/// semantic metadata and an explicit lightweight envelope warning.
Document import_ifc(const std::filesystem::path& path, std::string document_name, IfcExchangeReport* report = nullptr);

} // namespace tbe::core
