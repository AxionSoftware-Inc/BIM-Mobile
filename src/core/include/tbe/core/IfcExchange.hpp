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

// Keep the proven lightweight reader available as a compatibility fallback,
// but route production callers through the staged import pipeline below.  The
// source-specific macro is applied only to legacy IfcExchange.cpp by CMake, so
// its existing `import_ifc` definition is emitted as `import_ifc_legacy`
// without rewriting the 2x3/IFC4 compatibility code in place.
#ifdef TBE_LEGACY_IFC_IMPORT_IMPL
#define import_ifc import_ifc_legacy
#endif

/// Production import entrypoint. It preserves the semantic importer and then
/// recovers modern IFC4 tessellated products that the lightweight reader could
/// not decode, keeping render geometry and BIM identity in the same document.
Document import_ifc(const std::filesystem::path& path, std::string document_name, IfcExchangeReport* report = nullptr);

#ifndef TBE_LEGACY_IFC_IMPORT_IMPL
/// Compatibility stage used by the production pipeline. New code should call
/// import_ifc rather than depending on this function directly.
Document import_ifc_legacy(const std::filesystem::path& path, std::string document_name, IfcExchangeReport* report = nullptr);
#endif

} // namespace tbe::core
