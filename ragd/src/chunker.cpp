#include "chunker.hpp"
#include <algorithm>
#include <cctype>
#include <iterator>
#include <stdexcept>
#include <utility>

namespace ragd {
namespace {

struct Section {
    std::string heading;
    std::vector<std::string> paragraphs;
};

struct PageBlock {
    int page = 0;
    std::string text;
};

std::string normalize_newlines(const std::string& in) {
    std::string out;
    out.reserve(in.size());
    for (std::size_t i = 0; i < in.size(); ++i) {
        if (in[i] == '\r') {
            if (i + 1 < in.size() && in[i + 1] == '\n') ++i;
            out.push_back('\n');
        } else {
            out.push_back(in[i]);
        }
    }
    return out;
}

std::vector<PageBlock> split_pages(const std::string& normalized) {
    std::vector<PageBlock> out;
    PageBlock current;
    bool saw_marker = false;
    std::size_t start = 0;
    while (start <= normalized.size()) {
        std::size_t end = normalized.find('\n', start);
        if (end == std::string::npos) end = normalized.size();
        const std::string line = normalized.substr(start, end - start);
        int page = 0;
        if (line.rfind("=== Page ", 0) == 0) {
            const std::size_t n0 = 9;
            const std::size_t slash = line.find('/', n0);
            const std::size_t tail = line.rfind(" ===");
            if (slash != std::string::npos && tail != std::string::npos && slash > n0) {
                try { page = std::stoi(line.substr(n0, slash - n0)); } catch (...) { page = 0; }
            }
        }
        if (page > 0) {
            saw_marker = true;
            if (!current.text.empty()) out.push_back(std::move(current));
            current = PageBlock{};
            current.page = page;
        } else {
            if (!current.text.empty()) current.text.push_back('\n');
            current.text += line;
        }
        if (end == normalized.size()) break;
        start = end + 1;
    }
    if (!current.text.empty()) out.push_back(std::move(current));
    if (!saw_marker) {
        out.clear();
        out.push_back(PageBlock{0, normalized});
    }
    return out;
}

std::string trim_copy(const std::string& s) {
    std::size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
    return s.substr(a, b - a);
}

std::size_t utf8_back(const std::string& s, std::size_t p) {
    p = std::min(p, s.size());
    while (p > 0 && p < s.size() && (static_cast<unsigned char>(s[p]) & 0xC0) == 0x80) --p;
    return p;
}

std::size_t word_count(const std::string& s) {
    std::size_t words = 0;
    bool in_word = false;
    for (unsigned char c : s) {
        const bool ws = std::isspace(c) != 0;
        if (!ws && !in_word) ++words;
        in_word = !ws;
    }
    return words;
}

std::size_t line_count(const std::string& s) {
    return s.empty() ? 0 : 1 + static_cast<std::size_t>(std::count(s.begin(), s.end(), '\n'));
}

bool looks_like_heading(const std::string& raw) {
    const std::string s = trim_copy(raw);
    if (s.empty() || s.size() > 160 || line_count(s) > 2) return false;

    const std::size_t words = word_count(s);
    if (words == 0 || words > 14) return false;

    // Markdown headings and short numbered section titles are strong signals.
    if (s[0] == '#') return true;

    // A normal prose sentence ending in terminal punctuation should not become a heading.
    const char last = s.back();
    if (last == '?' || last == '!') return false;
    if (last == '.') {
        // Permit very short numeric labels such as "1." but reject ordinary sentences.
        bool numeric_label = true;
        for (std::size_t i = 0; i + 1 < s.size(); ++i) {
            const unsigned char c = static_cast<unsigned char>(s[i]);
            if (!(std::isdigit(c) || std::isspace(c) || c == '.' || c == '-')) {
                numeric_label = false;
                break;
            }
        }
        if (!numeric_label) return false;
    }

    // Long comma-heavy text is almost certainly prose, even without a final full stop.
    const std::size_t commas = static_cast<std::size_t>(std::count(s.begin(), s.end(), ','));
    if (commas >= 2 && words > 7) return false;

    return true;
}

std::vector<std::string> split_paragraphs(const std::string& s) {
    std::vector<std::string> out;
    std::size_t start = 0;
    std::size_t i = 0;

    while (i <= s.size()) {
        bool boundary = (i == s.size());
        std::size_t end = i;
        std::size_t next = i + 1;

        if (!boundary && s[i] == '\n') {
            std::size_t j = i;
            int newlines = 0;
            while (j < s.size() && (s[j] == '\n' || s[j] == ' ' || s[j] == '\t')) {
                if (s[j] == '\n') ++newlines;
                ++j;
            }
            if (newlines >= 2) {
                boundary = true;
                end = i;
                next = j;
            }
        }

        if (boundary) {
            auto p = trim_copy(s.substr(start, end - start));
            if (!p.empty()) out.push_back(std::move(p));
            start = next;
            i = next;
            if (i > s.size()) break;
            continue;
        }
        ++i;
    }
    return out;
}

std::vector<Section> make_sections(const std::vector<std::string>& paragraphs) {
    std::vector<Section> sections;
    Section current;

    auto flush = [&]() {
        if (!current.heading.empty() || !current.paragraphs.empty()) {
            sections.push_back(std::move(current));
            current = Section{};
        }
    };

    for (const auto& p : paragraphs) {
        if (looks_like_heading(p)) {
            if (current.paragraphs.empty() && !current.heading.empty()) {
                // Consecutive short headings usually represent title/subtitle hierarchy.
                current.heading += "\n";
                current.heading += p;
            } else {
                flush();
                current.heading = p;
            }
        } else {
            current.paragraphs.push_back(p);
        }
    }
    flush();
    return sections;
}

std::size_t find_soft_boundary(const std::string& s, std::size_t start, std::size_t desired, std::size_t max_end) {
    desired = std::min(desired, s.size());
    max_end = std::min(max_end, s.size());
    if (desired >= s.size()) return s.size();

    const std::size_t floor = start + (desired - start) * 2 / 3;
    for (std::size_t p = desired; p > floor; --p) {
        const char c = s[p - 1];
        if (c == '\n') return utf8_back(s, p);
        if ((c == '.' || c == '!' || c == '?' || c == ';' || c == ':') &&
            p < s.size() && std::isspace(static_cast<unsigned char>(s[p]))) {
            return utf8_back(s, p);
        }
    }
    for (std::size_t p = desired; p < max_end; ++p) {
        const char c = s[p];
        if (c == '\n' || std::isspace(static_cast<unsigned char>(c))) return utf8_back(s, p + 1);
    }
    for (std::size_t p = desired; p > start; --p) {
        if (std::isspace(static_cast<unsigned char>(s[p - 1]))) return utf8_back(s, p);
    }
    return utf8_back(s, desired);
}

std::vector<std::string> split_large_text(const std::string& block, std::size_t target_chars,
                                          std::size_t max_chars, std::size_t overlap_chars) {
    std::vector<std::string> out;
    if (block.empty()) return out;

    std::size_t start = 0;
    while (start < block.size()) {
        const std::size_t remaining = block.size() - start;
        if (remaining <= max_chars) {
            auto tail = trim_copy(block.substr(start));
            if (!tail.empty()) out.push_back(std::move(tail));
            break;
        }

        const std::size_t desired = std::min(start + target_chars, block.size());
        const std::size_t max_end = std::min(start + max_chars, block.size());
        std::size_t end = find_soft_boundary(block, start, desired, max_end);
        if (end <= start) end = max_end;

        auto piece = trim_copy(block.substr(start, end - start));
        if (!piece.empty()) out.push_back(std::move(piece));
        if (end >= block.size()) break;

        std::size_t next = end;
        if (overlap_chars > 0 && end > overlap_chars) {
            next = utf8_back(block, end - overlap_chars);
            while (next < end && !std::isspace(static_cast<unsigned char>(block[next]))) ++next;
            while (next < end && std::isspace(static_cast<unsigned char>(block[next]))) ++next;
        }
        if (next <= start) next = end;
        start = next;
    }
    return out;
}

std::string join_section(const Section& section) {
    std::string out = section.heading;
    for (const auto& p : section.paragraphs) {
        if (!out.empty()) out += "\n\n";
        out += p;
    }
    return out;
}

std::vector<std::string> split_section(const Section& section, const ChunkerConfig& cfg) {
    const std::string whole = join_section(section);
    if (whole.empty()) return {};
    if (whole.size() <= cfg.max_chars) return {whole};

    // No detected heading: paragraph-aware packing first, hard split only for oversized paragraphs.
    if (section.heading.empty()) {
        std::vector<std::string> units;
        for (const auto& p : section.paragraphs) {
            if (p.size() <= cfg.max_chars) {
                units.push_back(p);
            } else {
                auto pieces = split_large_text(p, cfg.target_chars, cfg.max_chars, cfg.overlap_chars);
                units.insert(units.end(), std::make_move_iterator(pieces.begin()), std::make_move_iterator(pieces.end()));
            }
        }

        std::vector<std::string> out;
        std::string current;
        for (const auto& unit : units) {
            if (current.empty()) {
                current = unit;
                continue;
            }
            const std::size_t proposed = current.size() + 2 + unit.size();
            if (proposed <= cfg.target_chars || (current.size() < cfg.target_chars / 2 && proposed <= cfg.max_chars)) {
                current += "\n\n";
                current += unit;
            } else {
                out.push_back(trim_copy(current));
                current = unit;
            }
        }
        if (!trim_copy(current).empty()) out.push_back(trim_copy(current));
        return out;
    }

    // Structured section: keep the heading as context on every child chunk.
    const std::string prefix = section.heading + "\n\n";
    if (prefix.size() >= cfg.max_chars) {
        return split_large_text(whole, cfg.target_chars, cfg.max_chars, cfg.overlap_chars);
    }

    const std::size_t body_max = cfg.max_chars - prefix.size();
    const std::size_t body_target = std::max<std::size_t>(64, std::min(cfg.target_chars, cfg.max_chars) - std::min(prefix.size(), cfg.target_chars / 2));
    const std::size_t body_overlap = std::min(cfg.overlap_chars, body_target > 1 ? body_target - 1 : 0);

    std::vector<std::string> units;
    for (const auto& p : section.paragraphs) {
        if (p.size() <= body_max) {
            units.push_back(p);
        } else {
            auto pieces = split_large_text(p, std::min(body_target, body_max), body_max, std::min(body_overlap, body_max / 2));
            units.insert(units.end(), std::make_move_iterator(pieces.begin()), std::make_move_iterator(pieces.end()));
        }
    }

    if (units.empty()) return {section.heading};

    std::vector<std::string> out;
    std::string body;
    auto flush = [&]() {
        auto t = trim_copy(body);
        if (!t.empty()) out.push_back(prefix + t);
        body.clear();
    };

    for (const auto& unit : units) {
        if (body.empty()) {
            body = unit;
            continue;
        }
        const std::size_t proposed_body = body.size() + 2 + unit.size();
        const std::size_t proposed_total = prefix.size() + proposed_body;
        if (proposed_total <= cfg.target_chars || (prefix.size() + body.size() < cfg.target_chars / 2 && proposed_total <= cfg.max_chars)) {
            body += "\n\n";
            body += unit;
        } else {
            flush();
            body = unit;
        }
    }
    flush();
    return out;
}

} // namespace

std::vector<ChunkInput> Chunker::split(const std::string& text) const {
    if (cfg_.target_chars < 128 || cfg_.max_chars < cfg_.target_chars || cfg_.overlap_chars >= cfg_.target_chars) {
        throw std::runtime_error("Invalid chunker configuration");
    }

    const std::string normalized = normalize_newlines(text);
    const auto pages = split_pages(normalized);

    std::vector<ChunkInput> result;
    for (const auto& page_block : pages) {
        const auto paragraphs = split_paragraphs(page_block.text);
        const auto sections = make_sections(paragraphs);
        for (const auto& section : sections) {
            auto chunks = split_section(section, cfg_);
            for (auto& text_chunk : chunks) {
                auto t = trim_copy(text_chunk);
                if (!t.empty()) {
                    ChunkInput ci;
                    ci.ordinal = static_cast<int>(result.size());
                    ci.text = std::move(t);
                    ci.page = page_block.page;
                    ci.section = trim_copy(section.heading);
                    result.push_back(std::move(ci));
                }
            }
        }
    }
    return result;
}

} // namespace ragd
