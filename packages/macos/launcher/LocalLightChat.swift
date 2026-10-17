import AppKit
import Foundation
import Security
import Darwin

// Native Dock + menu-bar launcher. Never writes into its signed .app bundle.
// macOS 11+, arm64 / x86_64 (combined by build_app.sh).

final class Services: NSObject, NSApplicationDelegate {
    private let fm = FileManager.default
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var processes: [String: Process] = [:]
    private var logHandles: [FileHandle] = []
    private var started = false
    private var launching = false
    private var timer: Timer?
    private final class HTTPResult {
        private let lock = NSLock()
        private var available = false
        func set(_ value: Bool) { lock.lock(); available = value; lock.unlock() }
        func get() -> Bool { lock.lock(); defer { lock.unlock() }; return available }
    }

    private lazy var contents = Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true)
    private lazy var helpers = contents.appendingPathComponent("Helpers", isDirectory: true)
    private lazy var resources = contents.appendingPathComponent("Resources", isDirectory: true)
    private lazy var webroot = resources.appendingPathComponent("www", isDirectory: true)
    private lazy var data: URL = {
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("LocalLightChat", isDirectory: true)
    }()
    private lazy var cache: URL = {
        let root = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("LocalLightChat", isDirectory: true)
    }()
    private lazy var logs = fm.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LocalLightChat", isDirectory: true)
    private var config: URL { data.appendingPathComponent("config", isDirectory: true) }
    private var run: URL { cache.appendingPathComponent("run", isDirectory: true) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "LLC"
        let menu = NSMenu()
        statusLine = NSMenuItem(title: "Stopped", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open LocalLightChat", action: #selector(openBrowser), keyEquivalent: "o"))
        startItem = NSMenuItem(title: "Start Services", action: #selector(startSelected), keyEquivalent: "s")
        stopItem = NSMenuItem(title: "Stop Services", action: #selector(stopSelected), keyEquivalent: "t")
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(NSMenuItem(title: "Restart Services", action: #selector(restartSelected), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Agent Config", action: #selector(openAgentConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open RAG Config", action: #selector(openRAGConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Data Folder", action: #selector(openData), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Logs", action: #selector(openLogs), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Initial Password File", action: #selector(openPassword), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LocalLightChat", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        installApplicationMenu()
        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        DispatchQueue.main.async { self.startSelected() }
    }

    // Right-click on the Dock icon: control services without a separate window.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dock = NSMenu()
        let browser = NSMenuItem(title: "Open LocalLightChat", action: #selector(openBrowser), keyEquivalent: "")
        let start = NSMenuItem(title: "Start Services", action: #selector(startSelected), keyEquivalent: "")
        let stop = NSMenuItem(title: "Stop Services", action: #selector(stopSelected), keyEquivalent: "")
        let restart = NSMenuItem(title: "Restart Services", action: #selector(restartSelected), keyEquivalent: "")
        let agentConfig = NSMenuItem(title: "Open Agent Config", action: #selector(openAgentConfig), keyEquivalent: "")
        let ragConfig = NSMenuItem(title: "Open RAG Config", action: #selector(openRAGConfig), keyEquivalent: "")
        let data = NSMenuItem(title: "Show Data Folder", action: #selector(openData), keyEquivalent: "")
        let logs = NSMenuItem(title: "Show Logs", action: #selector(openLogs), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit LocalLightChat", action: #selector(quit), keyEquivalent: "")
        start.isEnabled = !started && !launching
        stop.isEnabled = started
        restart.isEnabled = !launching
        for item in [browser, start, stop, restart, agentConfig, ragConfig, data, logs, quit] { item.target = self }
        dock.addItem(browser)
        dock.addItem(NSMenuItem.separator())
        dock.addItem(start)
        dock.addItem(stop)
        dock.addItem(restart)
        dock.addItem(NSMenuItem.separator())
        dock.addItem(agentConfig)
        dock.addItem(ragConfig)
        dock.addItem(NSMenuItem.separator())
        dock.addItem(data)
        dock.addItem(logs)
        dock.addItem(NSMenuItem.separator())
        dock.addItem(quit)
        return dock
    }

    // Clicking the Dock icon again opens the web UI, not a control window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openBrowser()
        return true
    }

    private func installApplicationMenu() {
        let menuBar = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationItem.submenu = applicationMenu
        menuBar.addItem(applicationItem)
        let items: [(String, Selector, String)] = [
            ("Open LocalLightChat", #selector(openBrowser), "o"),
            ("Start Services", #selector(startSelected), "s"),
            ("Stop Services", #selector(stopSelected), "t"),
            ("Restart Services", #selector(restartSelected), ""),
            ("Open Agent Config", #selector(openAgentConfig), ""),
            ("Open RAG Config", #selector(openRAGConfig), ""),
            ("Show Data Folder", #selector(openData), ""),
            ("Show Logs", #selector(openLogs), ""),
            ("Quit LocalLightChat", #selector(quit), "q")
        ]
        for (i, spec) in items.enumerated() {
            if i == 1 || i == 4 || i == 6 || i == 8 { applicationMenu.addItem(.separator()) }
            let item = NSMenuItem(title: spec.0, action: spec.1, keyEquivalent: spec.2)
            item.target = self
            applicationMenu.addItem(item)
        }
        NSApplication.shared.mainMenu = menuBar
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopAll()
        return .terminateNow
    }

    private func mkdir(_ u: URL) throws {
        try fm.createDirectory(at: u, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
    }

    private func writeOnce(_ url: URL, _ text: String, perms: Int = 0o600) throws {
        if !fm.fileExists(atPath: url.path) {
            try text.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path)
        }
    }

    private func writeAlways(_ url: URL, _ text: String) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func initialAdminPassword() throws -> String {
        // Development builds intentionally allow admin/admin for reproducible tests.
        // Production builds must disable LLCDevAdminLogin in Info.plist.
        if (Bundle.main.object(forInfoDictionaryKey: "LLCDevAdminLogin") as? Bool) == true {
            return "admin"
        }
        return try randomSecret()
    }

    private func randomSecret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw NSError(domain: "LocalLightChat", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Secure random number generation failed"])
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func nginxValue(_ str: String) -> String {
        // Paths are quoted, and Nginx's variable/meta characters are escaped.
        "\"" + str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$") + "\""
    }

    private func phpValue(_ str: String) -> String {
        // FPM INI env[] values are quoted; avoid untrusted newline injection.
        "\"" + str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func checkPaths() throws {
        for p in [data.path, cache.path, logs.path, webroot.path] {
            if p.contains("\n") || p.contains("\r") { throw NSError(domain: "LocalLightChat", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported newline in path: \(p)"]) }
        }
    }

    private func prepareDirectories() throws {
        try checkPaths()
        for p in [data, config, data.appendingPathComponent("db"),
                  data.appendingPathComponent("uploads"), data.appendingPathComponent("tmp"),
                  data.appendingPathComponent("artifacts"), data.appendingPathComponent("workspaces"),
                  data.appendingPathComponent("models"), data.appendingPathComponent("rag"),
                  data.appendingPathComponent("rag/indexes"), data.appendingPathComponent("certs"),
                  data.appendingPathComponent("logs"), logs, cache, run,
                  run.appendingPathComponent("nginx"), run.appendingPathComponent("nginx/client_body_temp"),
                  run.appendingPathComponent("nginx/fastcgi_temp"), run.appendingPathComponent("nginx/proxy_temp"),
                  run.appendingPathComponent("nginx/scgi_temp"), run.appendingPathComponent("nginx/uwsgi_temp"),
                  run.appendingPathComponent("php"), run.appendingPathComponent("php/sessions")] {
            try mkdir(p)
        }
        let admin = config.appendingPathComponent("initial-admin-password.txt")
        if !fm.fileExists(atPath: admin.path) {
            try writeOnce(admin, try initialAdminPassword() + "\n")
        }
        let token = config.appendingPathComponent("mcp-token.txt")
        if !fm.fileExists(atPath: token.path) {
            try writeOnce(token, try randomSecret() + "\n")
        }
    }

    private func readSecret(_ name: String) throws -> String {
        try String(contentsOf: config.appendingPathComponent(name), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runCommand(_ executable: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LocalLightChat", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Command failed: \(executable) (exit \(process.terminationStatus))"])
        }
    }

    private func ensureTLS() -> Bool {
        let cert = data.appendingPathComponent("certs/localhost.crt")
        let key = data.appendingPathComponent("certs/localhost.key")
        if fm.fileExists(atPath: cert.path) && fm.fileExists(atPath: key.path) { return true }
        let openssl = "/usr/bin/openssl"
        guard fm.isExecutableFile(atPath: openssl) else { return false }
        do {
            let opensslConfig = config.appendingPathComponent("openssl-localhost.cnf")
            try writeOnce(opensslConfig, """
                [ req ]
                default_bits = 2048
                prompt = no
                distinguished_name = dn
                x509_extensions = ext
                [ dn ]
                CN = localhost
                [ ext ]
                subjectAltName = DNS:localhost,IP:127.0.0.1
                basicConstraints = critical,CA:FALSE
                keyUsage = digitalSignature,keyEncipherment
                extendedKeyUsage = serverAuth
                """ + "\n")
            try runCommand(openssl, ["req", "-new", "-x509", "-nodes", "-newkey", "rsa:2048",
                                     "-sha256", "-days", "825", "-config", opensslConfig.path,
                                     "-extensions", "ext", "-keyout", key.path, "-out", cert.path])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
            return true
        } catch {
            try? fm.removeItem(at: cert)
            try? fm.removeItem(at: key)
            NSLog("LocalLightChat: TLS initialization failed: %@", String(describing: error))
            return false
        }
    }

    // These two files are user-owned: create only when absent, never overwrite edits.
    @discardableResult
    private func ensureAgentConfig() throws -> String {
        var token = try readSecret("mcp-token.txt")
        guard token.count >= 16 else {
            throw NSError(domain: "LocalLightChat", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid MCP token"])
        }
        let mcpConfigURL = config.appendingPathComponent("mcp-server.json")
        if !fm.fileExists(atPath: mcpConfigURL.path) {
            let mcp: [String: Any] = [
                "server": ["address": "127.0.0.1", "port": 8765, "endpoint": "/mcp", "maximum_request_bytes": 1048576],
                "authentication": ["bearer_token": token],
                "cors": ["enabled": false, "allowed_origins": [String]()],
                "filesystem": ["enabled": true, "workspace_root": data.appendingPathComponent("workspaces").path, "allow_delete": true],
                "processes": ["enabled": true, "allow_process_exec": true, "allow_shell_exec": true,
                              "allow_process_start": true, "allow_shell_start": true,
                              "default_wait_ms": 3000, "maximum_wait_ms": 60000],
                "terminal": ["enabled": true],
                "desktop": ["enabled": true],
                "logging": ["file": logs.appendingPathComponent("mcp-server.log").path,
                            "maximum_file_bytes": 5242880,
                            "log_process_commands": false, "log_process_output": false]
            ]
            let json = try JSONSerialization.data(withJSONObject: mcp, options: [.prettyPrinted, .sortedKeys])
            try json.write(to: mcpConfigURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: mcpConfigURL.path)
        } else {
            // Do not silently desynchronize the webapp's initial token from a user-edited MCP config.
            let bytes = try Data(contentsOf: mcpConfigURL)
            if let obj = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
               let auth = obj["authentication"] as? [String: Any],
               let configured = auth["bearer_token"] as? String, !configured.isEmpty, configured != token {
                token = configured
                try writeAlways(config.appendingPathComponent("mcp-token.txt"), configured + "\n")
            }
        }
        return token
    }

    private func ensureRAGConfig() throws {
        let file = config.appendingPathComponent("ragd.conf")
        let originalStubMarker = "# Embeddings: configure your llama.cpp/OpenAI-compatible endpoint and model."

        // Never overwrite a user's RAG config. For new installs use the complete,
        // shipped template (located in signed, read-only .app resources).
        if !fm.fileExists(atPath: file.path) {
            let templateURL = resources.appendingPathComponent("config/ragd.conf.template")
            let template = try String(contentsOf: templateURL, encoding: .utf8)
            guard template.contains("__LLC_RAG_DB_PATH__") else {
                throw NSError(domain: "LocalLightChat", code: 8,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid bundled RAG config template"])
            }
            let expanded = template.replacingOccurrences(of: "__LLC_RAG_DB_PATH__",
                 with: data.appendingPathComponent("rag/ragd.sqlite3").path)
            try writeOnce(file, expanded)
            return
        }

        // One-time migration ONLY for our earlier, abbreviated macOS-generated
        // config. Keep the complete previous contents and every user-edited value.
        // Match its original marker to avoid rewriting custom configurations.
        let current = try String(contentsOf: file, encoding: .utf8)
        // Some earlier releases emitted the short file with no header comments.
        // Match its LocalLightChat-owned DB path too (as in the existing macOS build).
        let builtInDB = "db=" + data.appendingPathComponent("rag/ragd.sqlite3").path
        let builtInDBAlias = "db_path=" + data.appendingPathComponent("rag/ragd.sqlite3").path
        guard current.contains(originalStubMarker) ||
              current.split(separator: "\n").contains(where: {
                 let line = $0.trimmingCharacters(in: .whitespaces)
                 return line == builtInDB || line == builtInDBAlias
              }) else { return }
        let activeKeys = Set(current.split(separator: "\n").compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { return nil }
            guard let separator = line.firstIndex(of: "=") else { return nil }
            return String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        })

        // Existing short configurations previously used RAGD's own fallback values.
        // Use EXACTLY these defaults, not the new template's different chunk tuning,
        // so migration does not unexpectedly alter retrieval/chunking behavior.
        let defaults: [(String, String)] = [
            ("chunk_chars", "1800"),
            ("chunk_max_chars", "2800"),
            ("chunk_overlap", "200"),
            ("embedding_batch", "32"),
            ("default_top_k", "8"),
            ("max_top_k", "64"),
            ("hybrid_dense_k", "96"),
            ("hybrid_bm25_k", "32"),
            ("hybrid_rrf_k", "60"),
            ("reranker_max_bytes", "0"),
            ("max_request_bytes", "134217728")
        ]
        let additions = defaults.filter { !activeKeys.contains($0.0) }
        // Show optional credential/model fields even if they were absent from the
        // no-comment abbreviated config. Hints remain inactive by default.
        let hints: [(String, String)] = [
            ("llama_api_key", "# llama_api_key=your-secret-key"),
            ("reranker_url", "# reranker_url=http://127.0.0.1:8080"),
            ("reranker_model", "# reranker_model=reranker"),
            ("reranker_api_key", "# reranker_api_key=your-secret-key")
        ]
        let missingHints = hints.filter { !current.contains($0.0 + "=") }
        guard !additions.isEmpty || !missingHints.isEmpty else { return }

        // Keep a safety copy outside the signed .app on the first migration.
        let backup = config.appendingPathComponent("ragd.conf.before-full-config.bak")
        if !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: file, to: backup)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        let extra = (additions.map { "\($0.0)=\($0.1)" } +
                     missingHints.map { $0.1 }).joined(separator: "\n")
        let separator = current.hasSuffix("\n") ? "" : "\n"
        try writeAlways(file, current + separator + "\n" +
            "# Additional RAGD settings (automatically documented; existing values preserved)\n" +
            extra + "\n")
    }

    private func prepareConfigs() throws {
        let token = try ensureAgentConfig()
        let admin = try readSecret("initial-admin-password.txt")
        guard !admin.isEmpty else {
            throw NSError(domain: "LocalLightChat", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid initial admin password"])
        }

        // Runtime FPM config is always generated OUTSIDE the signed bundle.
        let fpm = """
            [global]
            pid = \(phpValue(run.appendingPathComponent("php/php-fpm.pid").path))
            error_log = \(phpValue(logs.appendingPathComponent("php-fpm.log").path))
            daemonize = no

            [www]
            listen = 127.0.0.1:9002
            pm = dynamic
            pm.max_children = 8
            pm.start_servers = 2
            pm.min_spare_servers = 1
            pm.max_spare_servers = 3
            catch_workers_output = yes
            clear_env = yes
            request_terminate_timeout = 999s
            php_admin_value[memory_limit] = 1024M
            php_admin_value[max_execution_time] = 999
            php_admin_value[max_input_time] = 999
            php_admin_value[post_max_size] = 200M
            php_admin_value[upload_max_filesize] = 200M
            php_admin_value[max_file_uploads] = 20
            php_admin_value[default_socket_timeout] = 999
            php_admin_value[sys_temp_dir] = \(phpValue(data.appendingPathComponent("tmp").path))
            php_admin_value[upload_tmp_dir] = \(phpValue(data.appendingPathComponent("tmp").path))
            php_admin_value[session.save_path] = \(phpValue(run.appendingPathComponent("php/sessions").path))
            env[PATH] = /usr/bin:/bin:/usr/sbin:/sbin
            env[HOME] = \(phpValue(fm.homeDirectoryForCurrentUser.path))
            env[LLC_DATA_DIR] = \(phpValue(data.path))
            env[LLC_MCP_TOKEN] = \(phpValue(token))
            env[LLC_ADMIN_PASSWORD] = \(phpValue(admin))
            """ + "\n"
        try writeAlways(config.appendingPathComponent("php-fpm.conf"), fpm)

        try ensureRAGConfig()

        let ssl = ensureTLS()
        let web = nginxValue(webroot.path)
        let upload = nginxValue(data.appendingPathComponent("uploads").path + "/")
        let mime = nginxValue(resources.appendingPathComponent("nginx/mime.types").path)
        let cert = nginxValue(data.appendingPathComponent("certs/localhost.crt").path)
        let key = nginxValue(data.appendingPathComponent("certs/localhost.key").path)
        let sslBlock = ssl ? """
            server {
              listen 127.0.0.1:8082 ssl;
              server_name localhost;
              ssl_certificate \(cert);
              ssl_certificate_key \(key);
              ssl_protocols TLSv1.2 TLSv1.3;
              \(serverLocations(root: web, uploads: upload))
            }
            """ : ""
        let nginx = """
            worker_processes 1;
            pid \(nginxValue(run.appendingPathComponent("nginx.pid").path));
            error_log \(nginxValue(logs.appendingPathComponent("nginx-error.log").path)) warn;
            events { worker_connections 1024; }
            http {
              include \(mime);
              default_type application/octet-stream;
              sendfile on;
              keepalive_timeout 65;
              access_log \(nginxValue(logs.appendingPathComponent("nginx-access.log").path));
              client_body_temp_path \(nginxValue(run.appendingPathComponent("nginx/client_body_temp").path));
              fastcgi_temp_path \(nginxValue(run.appendingPathComponent("nginx/fastcgi_temp").path));
              proxy_temp_path \(nginxValue(run.appendingPathComponent("nginx/proxy_temp").path));
              scgi_temp_path \(nginxValue(run.appendingPathComponent("nginx/scgi_temp").path));
              uwsgi_temp_path \(nginxValue(run.appendingPathComponent("nginx/uwsgi_temp").path));
              server {
                listen 127.0.0.1:8081;
                server_name localhost;
                \(serverLocations(root: web, uploads: upload))
              }
              \(sslBlock)
            }
            """ + "\n"
        try writeAlways(config.appendingPathComponent("nginx.conf"), nginx)
    }

    private func serverLocations(root: String, uploads: String) -> String {
        return """
            root \(root);
            index index.html index.php;
            client_max_body_size 200M;
            location / { try_files $uri $uri/ =404; }
            # Uploaded files remain externally located but retain their existing /uploads/ URLs.
            location ^~ /uploads/ {
              alias \(uploads);
              if ($uri ~* "\\.(php|phtml|phar|sqlite|db)$") { return 403; }
              add_header X-Content-Type-Options nosniff always;
            }
            location ~ /\\. { deny all; }
            location ~* "\\.(sqlite|sqlite3|db|log|bak|ini)$" { deny all; }
            location ~ \\.php$ {
              try_files $uri =404;
              fastcgi_pass 127.0.0.1:9002;
              fastcgi_index index.php;
              include \(nginxValue(resources.appendingPathComponent("nginx/fastcgi_params").path));
              fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
              fastcgi_buffering off;
              fastcgi_read_timeout 999s;
              fastcgi_send_timeout 999s;
              fastcgi_connect_timeout 999s;
            }
            error_page 500 502 503 504 /50x.html;
            """
    }

    private func start(_ name: String, _ file: String, args: [String], cwd: URL, logName: String) throws {
        let binary = helpers.appendingPathComponent(file)
        guard fm.isExecutableFile(atPath: binary.path) else {
            throw NSError(domain: "LocalLightChat", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Missing helper: \(binary.path)"])
        }
        let logFile = logs.appendingPathComponent(logName)
        if !fm.fileExists(atPath: logFile.path) { fm.createFile(atPath: logFile.path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: logFile.path) else {
            throw NSError(domain: "LocalLightChat", code: 6,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot open log: \(logFile.path)"])
        }
        handle.seekToEndOfFile()
        logHandles.append(handle)
        let p = Process()
        p.executableURL = binary
        p.arguments = args
        p.currentDirectoryURL = cwd
        p.standardOutput = handle
        p.standardError = handle
        var env = ProcessInfo.processInfo.environment
        env["TMPDIR"] = data.appendingPathComponent("tmp").path
        env["HOME"] = fm.homeDirectoryForCurrentUser.path
        p.environment = env
        try p.run()
        processes[name] = p
    }

    @objc private func startSelected() {
        guard !started && !launching else { return }
        launching = true
        updateStatus()
        do {
            try prepareDirectories()
            try prepareConfigs()
            if fm.isExecutableFile(atPath: helpers.appendingPathComponent("ragd").path) {
                try start("ragd", "ragd", args: ["--config", config.appendingPathComponent("ragd.conf").path],
                          cwd: data, logName: "ragd.log")
            }
            if fm.isExecutableFile(atPath: helpers.appendingPathComponent("mcp-server").path) {
                try start("mcp", "mcp-server", args: [config.appendingPathComponent("mcp-server.json").path],
                          cwd: data, logName: "mcp-server-stdout.log")
            }
            try start("php", "php-fpm", args: ["-F", "-y", config.appendingPathComponent("php-fpm.conf").path,
                                                "--prefix", run.appendingPathComponent("php").path],
                      cwd: run, logName: "php-fpm-stdout.log")
            try start("nginx", "nginx", args: ["-p", run.appendingPathComponent("nginx").path + "/",
                                                "-c", config.appendingPathComponent("nginx.conf").path,
                                                "-g", "daemon off;"],
                      cwd: run, logName: "nginx-stdout.log")
            started = true
            launching = false
            updateStatus()
            // Do not block the AppKit main thread while waiting for the HTTP endpoint.
            DispatchQueue.global(qos: .utility).async { [weak self] in
                for _ in 0..<40 {
                    guard let self = self else { return }
                    if self.httpIsReady() {
                        DispatchQueue.main.async { if self.started && self.processes["nginx"]?.isRunning == true && self.processes["php"]?.isRunning == true { self.openBrowser() } }
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                DispatchQueue.main.async { [weak self] in self?.showError("LocalLightChat did not respond on port 8081. Check the logs.") }
            }
        } catch {
            launching = false
            stopAll()
            showError(error.localizedDescription)
        }
    }

    private func httpIsReady() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:8081/") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        let result = HTTPResult()
        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            result.set(response != nil)
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 1.3)
        return result.get()
    }

    private func stopAll() {
        // Only stop children started by THIS launcher. Never pkill arbitrary nginx/php processes.
        for key in ["nginx", "php", "mcp", "ragd"] {
            if let p = processes[key], p.isRunning {
                // Nginx and PHP-FPM understand SIGQUIT as graceful shutdown.
                if key == "nginx" || key == "php" {
                    kill(p.processIdentifier, SIGQUIT)
                } else {
                    p.terminate()
                }
            }
        }
        for _ in 0..<30 {
            if processes.values.allSatisfy({ !$0.isRunning }) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        // If a child ignores SIGTERM, do not SIGKILL unrelated processes.
        for p in processes.values where p.isRunning { kill(p.processIdentifier, SIGKILL) }
        processes.removeAll()
        for h in logHandles { h.closeFile() }
        logHandles.removeAll()
        started = false
        updateStatus()
    }

    @objc private func stopSelected() { stopAll() }

    @objc private func restartSelected() {
        guard !launching else { return }
        if started { stopAll() }
        startSelected()
    }

    // Open user-editable configs in the user's preferred editor. Never edit .app resources.
    // When opening an existing file, do NOT parse it first: users must be able to fix
    // malformed JSON / settings even when the relevant daemon fails to start.
    private func openEditableConfig(_ name: String) {
        let file = config.appendingPathComponent(name)
        do {
            if !fm.fileExists(atPath: file.path) {
                try prepareDirectories()
                if name == "mcp-server.json" {
                    try ensureAgentConfig()
                } else if name == "ragd.conf" {
                    try ensureRAGConfig()
                }
            }
            guard fm.fileExists(atPath: file.path) else {
                throw NSError(domain: "LocalLightChat", code: 7,
                              userInfo: [NSLocalizedDescriptionKey: "Config file not found: \(file.path)"])
            }
            if !NSWorkspace.shared.open(file) {
                // On machines with no default editor for .conf/.json, fall back to TextEdit.
                try runCommand("/usr/bin/open", ["-a", "TextEdit", file.path])
            }
        } catch {
            showError("Cannot open \(name): \(error.localizedDescription)")
        }
    }

    @objc private func openAgentConfig() { openEditableConfig("mcp-server.json") }
    @objc private func openRAGConfig() { openEditableConfig("ragd.conf") }

    @objc private func openBrowser() { NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8081/")!) }
    @objc private func openData() { NSWorkspace.shared.open(data) }
    @objc private func openLogs() { NSWorkspace.shared.open(logs) }
    @objc private func openPassword() {
        NSWorkspace.shared.open(config.appendingPathComponent("initial-admin-password.txt"))
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func showError(_ message: String) {
        NSLog("LocalLightChat: %@", message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "LocalLightChat"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func updateStatus() {
        guard statusLine != nil else { return }
        let running = started && !processes.isEmpty && processes.values.allSatisfy({ $0.isRunning })
        statusLine.title = launching ? "Starting…" : (running ? "Running · localhost:8081" : (started ? "Degraded · check logs" : "Stopped"))
        startItem.isEnabled = !started && !launching
        stopItem.isEnabled = started
        statusItem.button?.title = running ? "LLC ●" : "LLC"
    }
}

let app = NSApplication.shared
let services = Services()
app.delegate = services
app.setActivationPolicy(.regular)
app.run()
