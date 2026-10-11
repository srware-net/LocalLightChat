#pragma once

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cerrno>
#include <cstring>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
using ragd_socket_t = SOCKET;
static constexpr ragd_socket_t RAGD_INVALID_SOCKET = INVALID_SOCKET;
#else
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
using ragd_socket_t = int;
static constexpr ragd_socket_t RAGD_INVALID_SOCKET = -1;
#endif

namespace ragd::http {

inline std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c){ return static_cast<char>(std::tolower(c)); });
    return s;
}

inline std::string trim(const std::string& s) {
    std::size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
    return s.substr(a, b - a);
}

class SocketRuntime {
public:
    SocketRuntime() {
#ifdef _WIN32
        WSADATA wsa{};
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) throw std::runtime_error("WSAStartup failed");
#endif
    }
    ~SocketRuntime() {
#ifdef _WIN32
        WSACleanup();
#endif
    }
};

inline void close_socket(ragd_socket_t s) {
    if (s == RAGD_INVALID_SOCKET) return;
#ifdef _WIN32
    closesocket(s);
#else
    ::close(s);
#endif
}

inline bool send_all(ragd_socket_t s, const char* data, std::size_t len) {
    std::size_t sent = 0;
    while (sent < len) {
#ifdef _WIN32
        int n = ::send(s, data + sent, static_cast<int>(std::min<std::size_t>(len - sent, 1u << 20)), 0);
#else
        ssize_t n = ::send(s, data + sent, len - sent, MSG_NOSIGNAL);
#endif
        if (n <= 0) return false;
        sent += static_cast<std::size_t>(n);
    }
    return true;
}

inline bool send_all(ragd_socket_t s, const std::string& data) { return send_all(s, data.data(), data.size()); }

struct Request {
    std::string method;
    std::string target;
    std::map<std::string, std::string> headers;
    std::string body;
};

struct Response {
    int status = 200;
    std::string content_type = "application/json; charset=utf-8";
    std::map<std::string, std::string> headers;
    std::string body;
};

inline const char* reason_phrase(int status) {
    switch (status) {
        case 200: return "OK";
        case 201: return "Created";
        case 202: return "Accepted";
        case 204: return "No Content";
        case 400: return "Bad Request";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 409: return "Conflict";
        case 413: return "Payload Too Large";
        case 422: return "Unprocessable Entity";
        case 500: return "Internal Server Error";
        case 502: return "Bad Gateway";
        case 503: return "Service Unavailable";
        default: return "HTTP";
    }
}

inline std::string serialize_response(const Response& r) {
    std::ostringstream os;
    os << "HTTP/1.1 " << r.status << ' ' << reason_phrase(r.status) << "\r\n";
    os << "Content-Type: " << r.content_type << "\r\n";
    os << "Content-Length: " << r.body.size() << "\r\n";
    os << "Connection: close\r\n";
    for (const auto& kv : r.headers) os << kv.first << ": " << kv.second << "\r\n";
    os << "\r\n";
    os << r.body;
    return os.str();
}

class Server {
public:
    using Handler = std::function<Response(const Request&)>;

    Server(std::string host, int port, Handler handler, std::size_t max_body = 64 * 1024 * 1024)
        : host_(std::move(host)), port_(port), handler_(std::move(handler)), max_body_(max_body) {}

    ~Server() { stop(); }

    void stop() {
        running_ = false;
        if (listen_socket_ != RAGD_INVALID_SOCKET) {
            close_socket(listen_socket_);
            listen_socket_ = RAGD_INVALID_SOCKET;
        }
    }

    void run() {
        addrinfo hints{};
        hints.ai_family = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_flags = AI_PASSIVE;
        addrinfo* result = nullptr;
        const std::string port_s = std::to_string(port_);
        const char* host_ptr = host_.empty() || host_ == "*" ? nullptr : host_.c_str();
        if (getaddrinfo(host_ptr, port_s.c_str(), &hints, &result) != 0) throw std::runtime_error("getaddrinfo failed for listen address");

        for (addrinfo* p = result; p; p = p->ai_next) {
            ragd_socket_t s = ::socket(p->ai_family, p->ai_socktype, p->ai_protocol);
            if (s == RAGD_INVALID_SOCKET) continue;
            int yes = 1;
            setsockopt(s, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&yes), sizeof(yes));
            if (::bind(s, p->ai_addr, static_cast<int>(p->ai_addrlen)) == 0 && ::listen(s, 64) == 0) {
                listen_socket_ = s;
                break;
            }
            close_socket(s);
        }
        freeaddrinfo(result);
        if (listen_socket_ == RAGD_INVALID_SOCKET) throw std::runtime_error("Could not bind HTTP server");

        running_ = true;
        std::cout << "ragd listening on http://" << host_ << ':' << port_ << "\n";
        while (running_) {
            sockaddr_storage addr{};
#ifdef _WIN32
            int len = sizeof(addr);
#else
            socklen_t len = sizeof(addr);
#endif
            ragd_socket_t client = ::accept(listen_socket_, reinterpret_cast<sockaddr*>(&addr), &len);
            if (client == RAGD_INVALID_SOCKET) {
                if (!running_) break;
                continue;
            }
            std::thread([this, client]() {
                handle_connection(client);
                close_socket(client);
            }).detach();
        }
    }

private:
    std::string host_;
    int port_;
    Handler handler_;
    std::size_t max_body_;
    std::atomic<bool> running_{false};
    ragd_socket_t listen_socket_ = RAGD_INVALID_SOCKET;

    static bool recv_more(ragd_socket_t s, std::string& buf) {
        char tmp[16384];
#ifdef _WIN32
        int n = ::recv(s, tmp, sizeof(tmp), 0);
#else
        ssize_t n = ::recv(s, tmp, sizeof(tmp), 0);
#endif
        if (n <= 0) return false;
        buf.append(tmp, static_cast<std::size_t>(n));
        return true;
    }

    void handle_connection(ragd_socket_t s) {
        Response response;
        try {
            std::string data;
            std::size_t header_end = std::string::npos;
            while ((header_end = data.find("\r\n\r\n")) == std::string::npos) {
                if (data.size() > 64 * 1024) throw std::runtime_error("HTTP headers too large");
                if (!recv_more(s, data)) throw std::runtime_error("Connection closed while reading headers");
            }

            Request req;
            std::istringstream hs(data.substr(0, header_end));
            std::string line;
            if (!std::getline(hs, line)) throw std::runtime_error("Missing request line");
            if (!line.empty() && line.back() == '\r') line.pop_back();
            {
                std::istringstream ls(line);
                std::string version;
                if (!(ls >> req.method >> req.target >> version)) throw std::runtime_error("Malformed request line");
                if (version.rfind("HTTP/", 0) != 0) throw std::runtime_error("Unsupported protocol");
            }
            while (std::getline(hs, line)) {
                if (!line.empty() && line.back() == '\r') line.pop_back();
                auto c = line.find(':');
                if (c == std::string::npos) continue;
                req.headers[lower(trim(line.substr(0, c)))] = trim(line.substr(c + 1));
            }

            std::size_t content_length = 0;
            auto it = req.headers.find("content-length");
            if (it != req.headers.end()) {
                content_length = static_cast<std::size_t>(std::stoull(it->second));
                if (content_length > max_body_) {
                    response.status = 413;
                    response.body = "{\"error\":\"payload_too_large\"}";
                    send_all(s, serialize_response(response));
                    return;
                }
            }
            const std::size_t body_start = header_end + 4;
            while (data.size() - body_start < content_length) {
                if (!recv_more(s, data)) throw std::runtime_error("Connection closed while reading body");
            }
            req.body.assign(data.data() + body_start, content_length);
            response = handler_(req);
        } catch (const std::exception& e) {
            response.status = 400;
            response.body = std::string("{\"error\":\"bad_request\",\"detail\":\"") + escape_json(e.what()) + "\"}";
        }
        send_all(s, serialize_response(response));
    }

    static std::string escape_json(const std::string& s) {
        std::string out;
        for (char c : s) {
            if (c == '"') out += "\\\"";
            else if (c == '\\') out += "\\\\";
            else if (c == '\n') out += "\\n";
            else if (c == '\r') out += "\\r";
            else if (c == '\t') out += "\\t";
            else out += c;
        }
        return out;
    }
};

struct Url {
    std::string host;
    int port = 80;
    std::string base_path;
};

inline Url parse_http_url(const std::string& url) {
    const std::string prefix = "http://";
    if (url.rfind(prefix, 0) != 0) throw std::runtime_error("Only http:// llama URLs are supported in ragd v0");
    std::string rest = url.substr(prefix.size());
    std::string authority;
    std::string path;
    auto slash = rest.find('/');
    if (slash == std::string::npos) authority = rest;
    else { authority = rest.substr(0, slash); path = rest.substr(slash); }
    if (authority.empty()) throw std::runtime_error("Invalid HTTP URL");

    Url u;
    u.base_path = path;
    if (!authority.empty() && authority.front() == '[') {
        auto close = authority.find(']');
        if (close == std::string::npos) throw std::runtime_error("Invalid IPv6 URL");
        u.host = authority.substr(1, close - 1);
        if (close + 1 < authority.size()) {
            if (authority[close + 1] != ':') throw std::runtime_error("Invalid IPv6 URL port");
            u.port = std::stoi(authority.substr(close + 2));
        }
    } else {
        auto colon = authority.rfind(':');
        if (colon != std::string::npos && authority.find(':') == colon) {
            u.host = authority.substr(0, colon);
            u.port = std::stoi(authority.substr(colon + 1));
        } else u.host = authority;
    }
    if (u.host.empty() || u.port <= 0 || u.port > 65535) throw std::runtime_error("Invalid HTTP URL host/port");
    return u;
}

struct ClientResponse {
    int status = 0;
    std::map<std::string, std::string> headers;
    std::string body;
};

inline std::string decode_chunked(const std::string& in) {
    std::size_t p = 0;
    std::string out;
    while (true) {
        auto eol = in.find("\r\n", p);
        if (eol == std::string::npos) throw std::runtime_error("Malformed chunked response");
        std::string size_s = in.substr(p, eol - p);
        auto semi = size_s.find(';');
        if (semi != std::string::npos) size_s.resize(semi);
        std::size_t n = 0;
        std::istringstream ss(size_s);
        ss >> std::hex >> n;
        if (ss.fail()) throw std::runtime_error("Malformed chunk size");
        p = eol + 2;
        if (n == 0) break;
        if (p + n + 2 > in.size()) throw std::runtime_error("Truncated chunked response");
        out.append(in, p, n);
        p += n;
        if (in.compare(p, 2, "\r\n") != 0) throw std::runtime_error("Malformed chunk terminator");
        p += 2;
    }
    return out;
}

inline ClientResponse post_json(const Url& u, const std::string& path, const std::string& body,
                                const std::vector<std::pair<std::string, std::string>>& headers = {}) {
    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* result = nullptr;
    const std::string port_s = std::to_string(u.port);
    if (getaddrinfo(u.host.c_str(), port_s.c_str(), &hints, &result) != 0) throw std::runtime_error("Could not resolve llama-server host");

    ragd_socket_t s = RAGD_INVALID_SOCKET;
    for (addrinfo* p = result; p; p = p->ai_next) {
        s = ::socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (s == RAGD_INVALID_SOCKET) continue;
        if (::connect(s, p->ai_addr, static_cast<int>(p->ai_addrlen)) == 0) break;
        close_socket(s); s = RAGD_INVALID_SOCKET;
    }
    freeaddrinfo(result);
    if (s == RAGD_INVALID_SOCKET) throw std::runtime_error("Could not connect to llama-server");

    std::string full_path = u.base_path;
    if (!full_path.empty() && full_path.back() == '/' && !path.empty() && path.front() == '/') full_path.pop_back();
    full_path += path;
    if (full_path.empty()) full_path = "/";

    std::ostringstream req;
    req << "POST " << full_path << " HTTP/1.1\r\n";
    req << "Host: " << u.host << ':' << u.port << "\r\n";
    req << "Content-Type: application/json\r\n";
    req << "Accept: application/json\r\n";
    req << "Content-Length: " << body.size() << "\r\n";
    req << "Connection: close\r\n";
    for (const auto& kv : headers) req << kv.first << ": " << kv.second << "\r\n";
    req << "\r\n" << body;
    const std::string wire = req.str();
    if (!send_all(s, wire)) { close_socket(s); throw std::runtime_error("Failed to write llama-server request"); }

    std::string raw;
    char buf[16384];
    while (true) {
#ifdef _WIN32
        int n = ::recv(s, buf, sizeof(buf), 0);
#else
        ssize_t n = ::recv(s, buf, sizeof(buf), 0);
#endif
        if (n == 0) break;
        if (n < 0) { close_socket(s); throw std::runtime_error("Failed to read llama-server response"); }
        raw.append(buf, static_cast<std::size_t>(n));
    }
    close_socket(s);

    auto he = raw.find("\r\n\r\n");
    if (he == std::string::npos) throw std::runtime_error("Malformed llama-server HTTP response");
    ClientResponse r;
    std::istringstream hs(raw.substr(0, he));
    std::string line;
    if (!std::getline(hs, line)) throw std::runtime_error("Missing HTTP status line");
    if (!line.empty() && line.back() == '\r') line.pop_back();
    {
        std::istringstream ls(line);
        std::string version;
        ls >> version >> r.status;
        if (r.status <= 0) throw std::runtime_error("Malformed HTTP status line");
    }
    while (std::getline(hs, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        auto c = line.find(':');
        if (c != std::string::npos) r.headers[lower(trim(line.substr(0, c)))] = trim(line.substr(c + 1));
    }
    r.body = raw.substr(he + 4);
    auto te = r.headers.find("transfer-encoding");
    if (te != r.headers.end() && lower(te->second).find("chunked") != std::string::npos) r.body = decode_chunked(r.body);
    else {
        auto cl = r.headers.find("content-length");
        if (cl != r.headers.end()) {
            std::size_t n = static_cast<std::size_t>(std::stoull(cl->second));
            if (r.body.size() < n) throw std::runtime_error("Truncated HTTP response body");
            r.body.resize(n);
        }
    }
    return r;
}

} // namespace ragd::http
