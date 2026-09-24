package com.vibekits.vibekits

import ffi.FFI
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedInputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/** Tiny PAD-only control/MCP fallback while the Flutter UI process is absent. */
internal class PadAdbFallbackServer {
    private val running = AtomicBoolean(false)
    private var control: ServerSocket? = null
    private var mcp: ServerSocket? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        Thread({
            for (attempt in 0 until 12) {
                if (!running.get()) return@Thread
                try {
                    control = ServerSocket(32148, 8, InetAddress.getByName("127.0.0.1"))
                    mcp = ServerSocket(32147, 8, InetAddress.getByName("127.0.0.1"))
                    serve(control!!, false)
                    serve(mcp!!, true)
                    return@Thread
                } catch (_: Exception) {
                    control?.close()
                    mcp?.close()
                    control = null
                    mcp = null
                    Thread.sleep(500)
                }
            }
        }, "PadAdbFallbackBind").start()
    }

    fun stop() {
        running.set(false)
        control?.close()
        mcp?.close()
        control = null
        mcp = null
    }

    private fun serve(server: ServerSocket, isMcp: Boolean) {
        Thread({
            while (running.get() && !server.isClosed) {
                try {
                    val client = server.accept()
                    Thread({ handle(client, isMcp) }, "PadAdbFallbackRequest").start()
                } catch (_: Exception) {
                    if (server.isClosed) return@Thread
                }
            }
        }, if (isMcp) "PadAdbFallbackMcp" else "PadAdbFallbackControl").start()
    }

    private fun authorized(callerId: String, port: Int): Boolean {
        if (!Regex("^[1-9][0-9]{5,15}$").matches(callerId)) return false
        val connections = JSONArray(FFI.harnessConnections())
        for (i in 0 until connections.length()) {
            val row = connections.optJSONObject(i) ?: continue
            if (row.optString("peerId") == callerId && row.optBoolean("authorized") &&
                !row.optBoolean("disconnected") &&
                row.optString("portForward").endsWith(":$port")) return true
        }
        return false
    }

    private fun handle(socket: Socket, isMcp: Boolean) {
        socket.use { client ->
            try {
                client.soTimeout = 5000
                val input = BufferedInputStream(client.getInputStream())
                val header = StringBuilder()
                while (header.length < 16384 && !header.endsWith("\r\n\r\n")) {
                    val byte = input.read()
                    if (byte < 0) return
                    header.append(byte.toChar())
                }
                if (!header.endsWith("\r\n\r\n")) return
                val lines = header.toString().split("\r\n")
                val path = lines.firstOrNull()?.split(' ')?.getOrNull(1) ?: return
                val headers = lines.drop(1).mapNotNull {
                    val at = it.indexOf(':')
                    if (at < 1) null else it.substring(0, at).lowercase() to it.substring(at + 1).trim()
                }.toMap()
                val length = headers["content-length"]?.toIntOrNull() ?: 0
                if (length !in 0..65536) return
                val body = ByteArray(length)
                var read = 0
                while (read < length) {
                    val amount = input.read(body, read, length - read)
                    if (amount < 0) return
                    read += amount
                }
                val caller = headers["x-vibekits-caller-id"].orEmpty()
                val port = if (isMcp) 32147 else 32148
                if (!authorized(caller, port)) {
                    reply(client, 403, JSONObject().put("ok", false).put("error", "forbidden"))
                    return
                }
                val request = JSONObject(String(body, Charsets.UTF_8))
                if (!isMcp && path == "/simulator/ssh-bootstrap") {
                    if (request.optString("callerId") != caller) return
                    reply(client, 200, JSONObject().put("ok", true).put("data",
                        JSONObject().put("platform", "android").put("sshSupported", false)
                            .put("authorized", true).put("peerId", caller)))
                    return
                }
                if (!isMcp || path != "/mcp") return
                val method = request.optString("method")
                if (method == "notifications/initialized") {
                    reply(client, 202, null)
                    return
                }
                val result = when (method) {
                    "initialize" -> JSONObject().put("protocolVersion", "2025-06-18")
                        .put("capabilities", JSONObject().put("tools", JSONObject()))
                        .put("serverInfo", JSONObject().put("name", "VibeKits PAD ADB fallback")
                            .put("version", "1"))
                    "tools/list" -> JSONObject().put("tools", JSONArray().put(JSONObject()
                        .put("name", "vibekits.simulator.status")
                        .put("title", "PAD ADB 状态")
                        .put("inputSchema", JSONObject().put("type", "object")
                            .put("properties", JSONObject()))))
                    "tools/call" -> {
                        if (request.optJSONObject("params")?.optString("name") !=
                            "vibekits.simulator.status") return
                        JSONObject().put("content", JSONArray().put(JSONObject()
                            .put("type", "text").put("text", "PAD 后台服务在线，远程 ADB 可连接")))
                    }
                    else -> return
                }
                reply(client, 200, JSONObject().put("jsonrpc", "2.0")
                    .put("id", request.opt("id")).put("result", result))
            } catch (_: Exception) {
                // A malformed or disconnected caller never takes down the relay.
            }
        }
    }

    private fun reply(socket: Socket, status: Int, body: JSONObject?) {
        val payload = body?.toString()?.toByteArray(Charsets.UTF_8) ?: ByteArray(0)
        val reason = if (status == 200) "OK" else if (status == 202) "Accepted" else "Forbidden"
        val header = "HTTP/1.1 $status $reason\r\nContent-Type: application/json\r\n" +
            "Content-Length: ${payload.size}\r\nConnection: close\r\n\r\n"
        socket.getOutputStream().write(header.toByteArray(Charsets.US_ASCII))
        socket.getOutputStream().write(payload)
        socket.getOutputStream().flush()
    }
}
