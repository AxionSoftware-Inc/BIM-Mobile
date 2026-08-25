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

/// Imports a Tablet BIM IFC export losslessly. For third-party IFC files the
/// importer currently reports an explicit warning until a full geometry
/// kernel-backed IFC parser is connected; it never silently invents geometry.
Document import_ifc(const std::filesystem::path& path, std::string document_name, IfcExchangeReport* report = nullptr);

} // namespace tbe::core
