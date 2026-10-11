#include "store.hpp"
#include <sqlite3.h>
#include <cctype>
#include <cstring>
#include <stdexcept>

namespace ragd {
namespace {

void check(int rc, sqlite3* db, const char* what) {
    if (rc != SQLITE_OK && rc != SQLITE_DONE && rc != SQLITE_ROW) {
        throw std::runtime_error(std::string(what) + ": " + (db ? sqlite3_errmsg(db) : "sqlite error"));
    }
}

class Stmt {
public:
    Stmt(sqlite3* db, const char* sql) { check(sqlite3_prepare_v2(db, sql, -1, &s_, nullptr), db, "sqlite prepare"); }
    ~Stmt() { if (s_) sqlite3_finalize(s_); }
    sqlite3_stmt* get() { return s_; }
    void reset() { sqlite3_reset(s_); sqlite3_clear_bindings(s_); }
private:
    sqlite3_stmt* s_ = nullptr;
};

void bind_text(sqlite3_stmt* s, int i, const std::string& v) {
    check(sqlite3_bind_text(s, i, v.c_str(), static_cast<int>(v.size()), SQLITE_TRANSIENT), sqlite3_db_handle(s), "sqlite bind text");
}
void bind_blob(sqlite3_stmt* s, int i, const std::vector<float>& v) {
    check(sqlite3_bind_blob(s, i, v.data(), static_cast<int>(v.size() * sizeof(float)), SQLITE_TRANSIENT), sqlite3_db_handle(s), "sqlite bind blob");
}
std::string col_text(sqlite3_stmt* s, int i) {
    const auto* p = reinterpret_cast<const char*>(sqlite3_column_text(s, i));
    int n = sqlite3_column_bytes(s, i);
    return p ? std::string(p, static_cast<std::size_t>(n)) : std::string();
}
std::vector<float> col_vector(sqlite3_stmt* s, int i, int dim) {
    const void* p = sqlite3_column_blob(s, i);
    int n = sqlite3_column_bytes(s, i);
    if (!p || dim <= 0 || n != dim * static_cast<int>(sizeof(float))) throw std::runtime_error("Corrupt embedding BLOB in ragd database");
    std::vector<float> v(static_cast<std::size_t>(dim));
    std::memcpy(v.data(), p, static_cast<std::size_t>(n));
    return v;
}
bool has_column(sqlite3* db, const char* table, const char* column) {
    std::string sql = std::string("PRAGMA table_info(") + table + ");";
    Stmt s(db, sql.c_str());
    while (sqlite3_step(s.get()) == SQLITE_ROW) {
        if (col_text(s.get(), 1) == column) return true;
    }
    return false;
}
std::string meta_value(sqlite3* db, const std::string& key) {
    Stmt s(db, "SELECT value FROM ragd_meta WHERE key=?;");
    bind_text(s.get(), 1, key);
    int rc = sqlite3_step(s.get());
    if (rc == SQLITE_DONE) return {};
    check(rc, db, "read metadata");
    return col_text(s.get(), 0);
}
void set_meta_value(sqlite3* db, const std::string& key, const std::string& value) {
    Stmt s(db, "INSERT INTO ragd_meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value;");
    bind_text(s.get(), 1, key);
    bind_text(s.get(), 2, value);
    check(sqlite3_step(s.get()), db, "write metadata");
}

} // namespace

std::string make_fts5_query(const std::string& query) {
    std::vector<std::string> terms;
    std::string term;
    auto flush = [&]() {
        if (term.empty()) return;
        std::string quoted = "\"";
        for (char c : term) {
            if (c == '"') quoted += "\"\"";
            else quoted += c;
        }
        quoted += '"';
        terms.push_back(std::move(quoted));
        term.clear();
    };

    for (unsigned char c : query) {
        // UTF-8 continuation/lead bytes are retained; ASCII punctuation is a boundary.
        if (c >= 0x80 || std::isalnum(c) || c == '_') term.push_back(static_cast<char>(c));
        else flush();
    }
    flush();

    std::string out;
    for (std::size_t i = 0; i < terms.size(); ++i) {
        if (i) out += " OR ";
        out += terms[i];
    }
    return out;
}

Store::Store(const std::string& path) {
    int rc = sqlite3_open_v2(path.c_str(), &db_, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nullptr);
    if (rc != SQLITE_OK) {
        std::string msg = db_ ? sqlite3_errmsg(db_) : "sqlite open failed";
        if (db_) sqlite3_close(db_);
        db_ = nullptr;
        throw std::runtime_error(msg);
    }
    sqlite3_busy_timeout(db_, 5000);
    init_schema();
}

Store::~Store() { if (db_) sqlite3_close(db_); }

void Store::exec(const char* sql) {
    char* err = nullptr;
    int rc = sqlite3_exec(db_, sql, nullptr, nullptr, &err);
    if (rc != SQLITE_OK) {
        std::string msg = err ? err : sqlite3_errmsg(db_);
        sqlite3_free(err);
        throw std::runtime_error(msg);
    }
}

void Store::init_schema() {
    std::lock_guard<std::mutex> lock(mutex_);
    exec("PRAGMA journal_mode=WAL;");
    exec("PRAGMA synchronous=NORMAL;");
    exec("PRAGMA foreign_keys=ON;");
    exec(R"SQL(
CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    owner TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT '',
    content_hash TEXT NOT NULL DEFAULT '',
    metadata_json TEXT NOT NULL DEFAULT '{}',
    created_at INTEGER NOT NULL DEFAULT (unixepoch()),
    updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);
CREATE TABLE IF NOT EXISTS chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,
    text TEXT NOT NULL,
    page INTEGER NOT NULL DEFAULT 0,
    section TEXT NOT NULL DEFAULT '',
    embedding BLOB NOT NULL,
    dim INTEGER NOT NULL,
    embedding_model TEXT NOT NULL,
    UNIQUE(document_id, ordinal)
);
CREATE INDEX IF NOT EXISTS idx_chunks_document ON chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_model ON chunks(embedding_model);
CREATE TABLE IF NOT EXISTS ragd_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
)SQL");
    if (!has_column(db_, "chunks", "page")) exec("ALTER TABLE chunks ADD COLUMN page INTEGER NOT NULL DEFAULT 0;");
    if (!has_column(db_, "chunks", "section")) exec("ALTER TABLE chunks ADD COLUMN section TEXT NOT NULL DEFAULT ''; ");

    // External-content FTS: chunks remains the source of truth and rowid == chunks.id.
    exec(R"SQL(
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    text,
    content='chunks',
    content_rowid='id',
    tokenize='unicode61'
);
CREATE TRIGGER IF NOT EXISTS chunks_fts_ai AFTER INSERT ON chunks BEGIN
    INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER IF NOT EXISTS chunks_fts_ad AFTER DELETE ON chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.id, old.text);
END;
CREATE TRIGGER IF NOT EXISTS chunks_fts_au AFTER UPDATE OF text ON chunks BEGIN
    INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.id, old.text);
    INSERT INTO chunks_fts(rowid, text) VALUES (new.id, new.text);
END;
)SQL");

    // Databases from dense-only ragd have chunks but no FTS metadata. Rebuild once.
    if (meta_value(db_, "fts_schema_version") != "1") {
        exec("INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild');");
        set_meta_value(db_, "fts_schema_version", "1");
    }
}

void Store::replace_document(const DocumentRecord& doc, const std::vector<PersistChunk>& chunks) {
    std::lock_guard<std::mutex> lock(mutex_);
    exec("BEGIN IMMEDIATE;");
    try {
        Stmt up(db_, R"SQL(
INSERT INTO documents(id, owner, name, source, content_hash, metadata_json, created_at, updated_at)
VALUES(?, ?, ?, ?, ?, ?, unixepoch(), unixepoch())
ON CONFLICT(id) DO UPDATE SET owner=excluded.owner, name=excluded.name, source=excluded.source,
content_hash=excluded.content_hash, metadata_json=excluded.metadata_json, updated_at=unixepoch();
)SQL");
        bind_text(up.get(), 1, doc.id); bind_text(up.get(), 2, doc.owner); bind_text(up.get(), 3, doc.name);
        bind_text(up.get(), 4, doc.source); bind_text(up.get(), 5, doc.content_hash); bind_text(up.get(), 6, doc.metadata_json);
        check(sqlite3_step(up.get()), db_, "upsert document");

        Stmt del(db_, "DELETE FROM chunks WHERE document_id=?;");
        bind_text(del.get(), 1, doc.id); check(sqlite3_step(del.get()), db_, "delete old chunks");

        Stmt ins(db_, "INSERT INTO chunks(document_id, ordinal, text, page, section, embedding, dim, embedding_model) VALUES(?, ?, ?, ?, ?, ?, ?, ?);");
        for (const auto& c : chunks) {
            if (c.embedding.empty()) throw std::runtime_error("Cannot persist empty embedding");
            bind_text(ins.get(), 1, doc.id);
            check(sqlite3_bind_int(ins.get(), 2, c.ordinal), db_, "bind ordinal");
            bind_text(ins.get(), 3, c.text);
            check(sqlite3_bind_int(ins.get(), 4, c.page), db_, "bind page");
            bind_text(ins.get(), 5, c.section);
            bind_blob(ins.get(), 6, c.embedding);
            check(sqlite3_bind_int(ins.get(), 7, static_cast<int>(c.embedding.size())), db_, "bind dim");
            bind_text(ins.get(), 8, c.embedding_model);
            check(sqlite3_step(ins.get()), db_, "insert chunk");
            ins.reset();
        }
        exec("COMMIT;");
    } catch (...) {
        try { exec("ROLLBACK;"); } catch (...) {}
        throw;
    }
}

bool Store::delete_document(const std::string& id) {
    std::lock_guard<std::mutex> lock(mutex_);
    Stmt s(db_, "DELETE FROM documents WHERE id=?;"); bind_text(s.get(), 1, id);
    check(sqlite3_step(s.get()), db_, "delete document"); return sqlite3_changes(db_) > 0;
}

std::vector<IndexEntry> Store::load_index(const std::string& embedding_model) {
    std::lock_guard<std::mutex> lock(mutex_);
    Stmt s(db_, R"SQL(
SELECT c.id, c.document_id, d.owner, c.ordinal, c.embedding, c.dim
FROM chunks c JOIN documents d ON d.id=c.document_id
WHERE c.embedding_model=? ORDER BY c.id;
)SQL");
    bind_text(s.get(), 1, embedding_model);
    std::vector<IndexEntry> out;
    while (true) {
        int rc = sqlite3_step(s.get()); if (rc == SQLITE_DONE) break; check(rc, db_, "load index");
        IndexEntry e; e.chunk_id = sqlite3_column_int64(s.get(), 0); e.document_id = col_text(s.get(), 1);
        e.owner = col_text(s.get(), 2); e.ordinal = sqlite3_column_int(s.get(), 3);
        e.embedding = col_vector(s.get(), 4, sqlite3_column_int(s.get(), 5)); out.push_back(std::move(e));
    }
    return out;
}

std::vector<SearchHit> Store::bm25_search(const std::string& query, std::size_t top_k, const SearchFilter& filter) {
    if (top_k == 0) return {};
    const std::string match = make_fts5_query(query);
    if (match.empty()) return {};

    std::lock_guard<std::mutex> lock(mutex_);
    std::string sql = R"SQL(
SELECT c.id, c.document_id, c.ordinal, bm25(chunks_fts)
FROM chunks_fts
JOIN chunks c ON c.id=chunks_fts.rowid
JOIN documents d ON d.id=c.document_id
WHERE chunks_fts MATCH ?
)SQL";
    if (!filter.owner.empty()) sql += " AND d.owner=?";
    if (!filter.document_ids.empty()) {
        sql += " AND c.document_id IN (";
        std::size_t n = 0;
        for (const auto& unused : filter.document_ids) { (void)unused; if (n++) sql += ','; sql += '?'; }
        sql += ')';
    }
    sql += " ORDER BY bm25(chunks_fts) ASC, c.id ASC LIMIT ?;";

    Stmt s(db_, sql.c_str());
    int bind = 1;
    bind_text(s.get(), bind++, match);
    if (!filter.owner.empty()) bind_text(s.get(), bind++, filter.owner);
    for (const auto& id : filter.document_ids) bind_text(s.get(), bind++, id);
    check(sqlite3_bind_int64(s.get(), bind, static_cast<sqlite3_int64>(top_k)), db_, "bind bm25 limit");

    std::vector<SearchHit> out;
    while (true) {
        const int rc = sqlite3_step(s.get());
        if (rc == SQLITE_DONE) break;
        check(rc, db_, "bm25 search");
        SearchHit h;
        h.chunk_id = sqlite3_column_int64(s.get(), 0);
        h.document_id = col_text(s.get(), 1);
        h.ordinal = sqlite3_column_int(s.get(), 2);
        // FTS5 bm25() is lower-is-better (commonly negative); expose higher-is-better.
        h.score = static_cast<float>(-sqlite3_column_double(s.get(), 3));
        out.push_back(std::move(h));
    }
    return out;
}

StoredChunk Store::get_chunk(std::int64_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    Stmt s(db_, R"SQL(
SELECT c.id, c.document_id, d.owner, c.ordinal, c.text, d.source, d.name, c.page, c.section, c.embedding, c.dim
FROM chunks c JOIN documents d ON d.id=c.document_id WHERE c.id=?;
)SQL");
    check(sqlite3_bind_int64(s.get(), 1, id), db_, "bind chunk id");
    int rc = sqlite3_step(s.get()); if (rc == SQLITE_DONE) throw std::runtime_error("Chunk disappeared from database"); check(rc, db_, "fetch chunk");
    StoredChunk c; c.id = sqlite3_column_int64(s.get(), 0); c.document_id = col_text(s.get(), 1); c.owner = col_text(s.get(), 2);
    c.ordinal = sqlite3_column_int(s.get(), 3); c.text = col_text(s.get(), 4); c.source = col_text(s.get(), 5); c.document_name = col_text(s.get(), 6);
    c.page = sqlite3_column_int(s.get(), 7); c.section = col_text(s.get(), 8); c.embedding = col_vector(s.get(), 9, sqlite3_column_int(s.get(), 10));
    return c;
}

std::int64_t Store::document_count() {
    std::lock_guard<std::mutex> lock(mutex_); Stmt s(db_, "SELECT count(*) FROM documents;"); check(sqlite3_step(s.get()), db_, "count documents"); return sqlite3_column_int64(s.get(), 0);
}
std::int64_t Store::chunk_count(const std::string& embedding_model) {
    std::lock_guard<std::mutex> lock(mutex_); Stmt s(db_, "SELECT count(*) FROM chunks WHERE embedding_model=?;"); bind_text(s.get(), 1, embedding_model);
    check(sqlite3_step(s.get()), db_, "count chunks"); return sqlite3_column_int64(s.get(), 0);
}

} // namespace ragd
