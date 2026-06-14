#include "tbe/core/Project.hpp"

#include <sstream>
#include <stdexcept>
#include <utility>

namespace tbe::core {

namespace {

std::string escape_json_string(std::string_view value) {
    std::string escaped;
    for (const auto ch : value) {
        if (ch == '"' || ch == '\\') {
            escaped.push_back('\\');
        }
        escaped.push_back(ch);
    }
    return escaped;
}

std::string unescape_json_string(std::string_view value) {
    std::string unescaped;
    unescaped.reserve(value.size());

    for (std::size_t index = 0; index < value.size(); ++index) {
        if (value[index] == '\\' && (index + 1) < value.size()) {
            ++index;
        }
        unescaped.push_back(value[index]);
    }

    return unescaped;
}

std::size_t find_json_string_end(std::string_view value, std::size_t start) {
    auto escaped = false;
    for (std::size_t index = start; index < value.size(); ++index) {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (value[index] == '\\') {
            escaped = true;
            continue;
        }
        if (value[index] == '"') {
            return index;
        }
    }
    return std::string_view::npos;
}

} // namespace

Project::Project(std::string name)
    : name_(std::move(name)),
      document_(name_ + " Model") {
    if (name_.empty()) {
        throw std::invalid_argument("project name must not be empty");
    }
}

std::string_view Project::name() const noexcept {
    return name_;
}

Document& Project::active_document() noexcept {
    return document_;
}

const Document& Project::active_document() const noexcept {
    return document_;
}

std::string Project::to_json() const {
    std::ostringstream out;
    out << "{\"schema\":\"tbe.project.v1\",";
    out << "\"project_name\":\"" << escape_json_string(name_) << "\",";
    out << "\"document\":" << document_.to_json() << '}';
    return out.str();
}

Project Project::from_json(std::string_view json) {
    const auto project_name_key = std::string_view{"\"project_name\":\""};
    const auto document_key = std::string_view{"\"document\":"};

    const auto project_name_start = json.find(project_name_key);
    const auto document_start = json.find(document_key);
    if (project_name_start == std::string_view::npos || document_start == std::string_view::npos) {
        throw std::invalid_argument("invalid project JSON");
    }

    const auto name_begin = project_name_start + project_name_key.size();
    const auto name_end = find_json_string_end(json, name_begin);
    if (name_end == std::string_view::npos) {
        throw std::invalid_argument("invalid project JSON name");
    }

    const auto doc_begin = document_start + document_key.size();
    const auto doc_end = json.rfind('}');
    if (doc_end == std::string_view::npos || doc_end <= doc_begin) {
        throw std::invalid_argument("invalid project JSON document");
    }

    Project project{unescape_json_string(json.substr(name_begin, name_end - name_begin))};
    project.document_ = Document::from_json(json.substr(doc_begin, doc_end - doc_begin));
    return project;
}

} // namespace tbe::core
