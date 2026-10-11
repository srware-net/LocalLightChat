#pragma once

#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <limits>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace ragd::json {

class Value {
public:
    using array_t = std::vector<Value>;
    using object_t = std::map<std::string, Value>;
    using storage_t = std::variant<std::nullptr_t, bool, double, std::string, array_t, object_t>;

    Value() : v_(nullptr) {}
    Value(std::nullptr_t) : v_(nullptr) {}
    Value(bool v) : v_(v) {}
    Value(int v) : v_(static_cast<double>(v)) {}
    Value(std::int64_t v) : v_(static_cast<double>(v)) {}
    Value(double v) : v_(v) {}
    Value(const char* v) : v_(std::string(v)) {}
    Value(std::string v) : v_(std::move(v)) {}
    Value(array_t v) : v_(std::move(v)) {}
    Value(object_t v) : v_(std::move(v)) {}

    static Value array() { return Value(array_t{}); }
    static Value object() { return Value(object_t{}); }

    bool is_null() const { return std::holds_alternative<std::nullptr_t>(v_); }
    bool is_bool() const { return std::holds_alternative<bool>(v_); }
    bool is_number() const { return std::holds_alternative<double>(v_); }
    bool is_string() const { return std::holds_alternative<std::string>(v_); }
    bool is_array() const { return std::holds_alternative<array_t>(v_); }
    bool is_object() const { return std::holds_alternative<object_t>(v_); }

    bool as_bool() const { return std::get<bool>(v_); }
    double as_number() const { return std::get<double>(v_); }
    int as_int() const { return static_cast<int>(std::get<double>(v_)); }
    std::int64_t as_i64() const { return static_cast<std::int64_t>(std::get<double>(v_)); }
    const std::string& as_string() const { return std::get<std::string>(v_); }
    std::string& as_string() { return std::get<std::string>(v_); }
    const array_t& as_array() const { return std::get<array_t>(v_); }
    array_t& as_array() { return std::get<array_t>(v_); }
    const object_t& as_object() const { return std::get<object_t>(v_); }
    object_t& as_object() { return std::get<object_t>(v_); }

    bool contains(const std::string& key) const {
        if (!is_object()) return false;
        return as_object().find(key) != as_object().end();
    }

    const Value& at(const std::string& key) const {
        if (!is_object()) throw std::runtime_error("JSON value is not an object");
        auto it = as_object().find(key);
        if (it == as_object().end()) throw std::runtime_error("Missing JSON field: " + key);
        return it->second;
    }

    Value& operator[](const std::string& key) {
        if (!is_object()) v_ = object_t{};
        return as_object()[key];
    }

    const Value& operator[](std::size_t i) const { return as_array().at(i); }
    Value& operator[](std::size_t i) { return as_array().at(i); }

    void push_back(Value v) {
        if (!is_array()) v_ = array_t{};
        as_array().push_back(std::move(v));
    }

    std::string string_or(const std::string& key, const std::string& fallback = {}) const {
        if (!is_object()) return fallback;
        auto it = as_object().find(key);
        return (it != as_object().end() && it->second.is_string()) ? it->second.as_string() : fallback;
    }

    int int_or(const std::string& key, int fallback) const {
        if (!is_object()) return fallback;
        auto it = as_object().find(key);
        return (it != as_object().end() && it->second.is_number()) ? it->second.as_int() : fallback;
    }

    bool bool_or(const std::string& key, bool fallback) const {
        if (!is_object()) return fallback;
        auto it = as_object().find(key);
        return (it != as_object().end() && it->second.is_bool()) ? it->second.as_bool() : fallback;
    }

private:
    storage_t v_;
};

namespace detail {

inline void append_utf8(std::string& out, std::uint32_t cp) {
    if (cp <= 0x7F) {
        out.push_back(static_cast<char>(cp));
    } else if (cp <= 0x7FF) {
        out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp <= 0xFFFF) {
        out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp <= 0x10FFFF) {
        out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
        throw std::runtime_error("Invalid Unicode code point");
    }
}

class Parser {
public:
    explicit Parser(const std::string& s) : s_(s) {}

    Value parse() {
        skip_ws();
        Value v = parse_value();
        skip_ws();
        if (pos_ != s_.size()) error("Trailing characters");
        return v;
    }

private:
    const std::string& s_;
    std::size_t pos_ = 0;

    [[noreturn]] void error(const std::string& msg) const {
        throw std::runtime_error("JSON parse error at byte " + std::to_string(pos_) + ": " + msg);
    }

    void skip_ws() {
        while (pos_ < s_.size() && (s_[pos_] == ' ' || s_[pos_] == '\t' || s_[pos_] == '\r' || s_[pos_] == '\n')) ++pos_;
    }

    char peek() const { return pos_ < s_.size() ? s_[pos_] : '\0'; }

    bool consume(char c) {
        if (peek() == c) { ++pos_; return true; }
        return false;
    }

    void expect(char c) {
        if (!consume(c)) error(std::string("Expected '") + c + "'");
    }

    Value parse_value() {
        if (pos_ >= s_.size()) error("Unexpected end of input");
        switch (peek()) {
            case 'n': parse_literal("null"); return Value(nullptr);
            case 't': parse_literal("true"); return Value(true);
            case 'f': parse_literal("false"); return Value(false);
            case '"': return Value(parse_string());
            case '[': return parse_array();
            case '{': return parse_object();
            default:
                if (peek() == '-' || (peek() >= '0' && peek() <= '9')) return Value(parse_number());
                error("Unexpected character");
        }
    }

    void parse_literal(const char* lit) {
        for (const char* p = lit; *p; ++p) {
            if (pos_ >= s_.size() || s_[pos_] != *p) error(std::string("Expected ") + lit);
            ++pos_;
        }
    }

    static int hexval(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    }

    std::uint32_t parse_hex4() {
        if (pos_ + 4 > s_.size()) error("Truncated Unicode escape");
        std::uint32_t v = 0;
        for (int i = 0; i < 4; ++i) {
            int h = hexval(s_[pos_++]);
            if (h < 0) error("Invalid Unicode escape");
            v = (v << 4) | static_cast<std::uint32_t>(h);
        }
        return v;
    }

    std::string parse_string() {
        expect('"');
        std::string out;
        while (pos_ < s_.size()) {
            unsigned char c = static_cast<unsigned char>(s_[pos_++]);
            if (c == '"') return out;
            if (c < 0x20) error("Control character in string");
            if (c != '\\') {
                out.push_back(static_cast<char>(c));
                continue;
            }
            if (pos_ >= s_.size()) error("Truncated escape");
            char e = s_[pos_++];
            switch (e) {
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                case '/': out.push_back('/'); break;
                case 'b': out.push_back('\b'); break;
                case 'f': out.push_back('\f'); break;
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case 'u': {
                    std::uint32_t cp = parse_hex4();
                    if (cp >= 0xD800 && cp <= 0xDBFF) {
                        if (pos_ + 2 > s_.size() || s_[pos_] != '\\' || s_[pos_ + 1] != 'u') error("Expected low surrogate");
                        pos_ += 2;
                        std::uint32_t low = parse_hex4();
                        if (low < 0xDC00 || low > 0xDFFF) error("Invalid low surrogate");
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                    } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
                        error("Unexpected low surrogate");
                    }
                    append_utf8(out, cp);
                    break;
                }
                default: error("Invalid escape");
            }
        }
        error("Unterminated string");
    }

    double parse_number() {
        std::size_t start = pos_;
        consume('-');
        if (consume('0')) {
        } else {
            if (peek() < '1' || peek() > '9') error("Invalid number");
            while (peek() >= '0' && peek() <= '9') ++pos_;
        }
        if (consume('.')) {
            if (peek() < '0' || peek() > '9') error("Invalid fraction");
            while (peek() >= '0' && peek() <= '9') ++pos_;
        }
        if (peek() == 'e' || peek() == 'E') {
            ++pos_;
            if (peek() == '+' || peek() == '-') ++pos_;
            if (peek() < '0' || peek() > '9') error("Invalid exponent");
            while (peek() >= '0' && peek() <= '9') ++pos_;
        }
        const std::string token = s_.substr(start, pos_ - start);
        char* end = nullptr;
        double v = std::strtod(token.c_str(), &end);
        if (!end || *end != '\0' || !std::isfinite(v)) error("Invalid number");
        return v;
    }

    Value parse_array() {
        expect('[');
        skip_ws();
        Value::array_t out;
        if (consume(']')) return Value(std::move(out));
        while (true) {
            skip_ws();
            out.push_back(parse_value());
            skip_ws();
            if (consume(']')) break;
            expect(',');
        }
        return Value(std::move(out));
    }

    Value parse_object() {
        expect('{');
        skip_ws();
        Value::object_t out;
        if (consume('}')) return Value(std::move(out));
        while (true) {
            skip_ws();
            if (peek() != '"') error("Expected object key");
            std::string key = parse_string();
            skip_ws();
            expect(':');
            skip_ws();
            out[std::move(key)] = parse_value();
            skip_ws();
            if (consume('}')) break;
            expect(',');
        }
        return Value(std::move(out));
    }
};

inline void dump_string(std::ostringstream& os, const std::string& s) {
    os << '"';
    static const char* hex = "0123456789abcdef";
    for (unsigned char c : s) {
        switch (c) {
            case '"': os << "\\\""; break;
            case '\\': os << "\\\\"; break;
            case '\b': os << "\\b"; break;
            case '\f': os << "\\f"; break;
            case '\n': os << "\\n"; break;
            case '\r': os << "\\r"; break;
            case '\t': os << "\\t"; break;
            default:
                if (c < 0x20) {
                    os << "\\u00" << hex[(c >> 4) & 0xF] << hex[c & 0xF];
                } else {
                    os << static_cast<char>(c);
                }
        }
    }
    os << '"';
}

inline void dump_value(std::ostringstream& os, const Value& v) {
    if (v.is_null()) { os << "null"; return; }
    if (v.is_bool()) { os << (v.as_bool() ? "true" : "false"); return; }
    if (v.is_number()) {
        const double d = v.as_number();
        if (std::floor(d) == d && std::fabs(d) < 9.0e15) os << std::fixed << std::setprecision(0) << d;
        else os << std::setprecision(17) << d;
        return;
    }
    if (v.is_string()) { dump_string(os, v.as_string()); return; }
    if (v.is_array()) {
        os << '[';
        bool first = true;
        for (const auto& x : v.as_array()) {
            if (!first) os << ',';
            first = false;
            dump_value(os, x);
        }
        os << ']';
        return;
    }
    os << '{';
    bool first = true;
    for (const auto& kv : v.as_object()) {
        if (!first) os << ',';
        first = false;
        dump_string(os, kv.first);
        os << ':';
        dump_value(os, kv.second);
    }
    os << '}';
}

} // namespace detail

inline Value parse(const std::string& s) { return detail::Parser(s).parse(); }
inline std::string dump(const Value& v) { std::ostringstream os; detail::dump_value(os, v); return os.str(); }

} // namespace ragd::json
