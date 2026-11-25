#pragma once
#include <string>
#include <vector>
#include <mutex>
#include <thread>
#include <atomic>
#include <cstring>
#include <cstdlib>
#include <chrono>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <mbedtls/net_sockets.h>
#include <mbedtls/ssl.h>
#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>

class SwitchWsClient {
public:
    SwitchWsClient() : connected_(false), running_(false) {}
    ~SwitchWsClient() { disconnect(); }

    bool connectToRelay(const std::string& host = "azusa.online", const std::string& port = "443", const std::string& path = "/ddz") {
        disconnect();
        running_ = true;
        worker_ = std::thread([this, host, port, path]() {
            runLoop(host, port, path);
        });
        return true;
    }

    void disconnect() {
        running_ = false;
        connected_ = false;
        if (worker_.joinable()) {
            worker_.join();
        }
        std::lock_guard<std::mutex> lk(mtx_);
        inbox_.clear();
        outbox_.clear();
    }

    bool isConnected() const { return connected_.load(); }

    void sendText(const std::string& jsonStr) {
        std::lock_guard<std::mutex> lk(mtx_);
        outbox_.push_back(jsonStr);
    }

    std::vector<std::string> pollMessages() {
        std::lock_guard<std::mutex> lk(mtx_);
        std::vector<std::string> res;
        res.swap(inbox_);
        return res;
    }

private:
    std::atomic<bool> connected_;
    std::atomic<bool> running_;
    std::mutex mtx_;
    std::vector<std::string> inbox_;
    std::vector<std::string> outbox_;
    std::thread worker_;

    static bool isTransientTlsRet(int r) {
        if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE) return true;
#ifdef MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET
        if (r == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) return true;
#endif
        if (r == -0x7880) return true;
        return false;
    }

    static void buildMaskedFrame(const std::string& payload, std::vector<uint8_t>& outFrame) {
        outFrame.clear();
        outFrame.push_back(0x81); // FIN + Text frame
        size_t len = payload.size();
        if (len <= 125) {
            outFrame.push_back(0x80 | (uint8_t)len);
        } else if (len <= 65535) {
            outFrame.push_back(0x80 | 126);
            outFrame.push_back((len >> 8) & 0xFF);
            outFrame.push_back(len & 0xFF);
        } else {
            outFrame.push_back(0x80 | 127);
            for (int i = 7; i >= 0; --i) outFrame.push_back((len >> (i * 8)) & 0xFF);
        }
        uint8_t mask[4] = {0x37, 0xFA, 0x21, 0x3D};
        for (int i = 0; i < 4; ++i) outFrame.push_back(mask[i]);
        for (size_t i = 0; i < len; ++i) {
            outFrame.push_back(((uint8_t)payload[i]) ^ mask[i & 3]);
        }
    }

    void runLoop(const std::string& host, const std::string& port, const std::string& path) {
        mbedtls_net_context server_fd;
        mbedtls_entropy_context entropy;
        mbedtls_ctr_drbg_context ctr_drbg;
        mbedtls_ssl_context ssl;
        mbedtls_ssl_config conf;

        mbedtls_net_init(&server_fd);
        mbedtls_ssl_init(&ssl);
        mbedtls_ssl_config_init(&conf);
        mbedtls_ctr_drbg_init(&ctr_drbg);
        mbedtls_entropy_init(&entropy);

        const char* pers = "htt_switch_ws";
        if (mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy, (const unsigned char*)pers, strlen(pers)) != 0) {
            goto cleanup;
        }
        if (mbedtls_net_connect(&server_fd, host.c_str(), port.c_str(), MBEDTLS_NET_PROTO_TCP) != 0) {
            goto cleanup;
        }
        if (mbedtls_ssl_config_defaults(&conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT) != 0) {
            goto cleanup;
        }
        mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
        mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);

        if (mbedtls_ssl_setup(&ssl, &conf) != 0) goto cleanup;
        mbedtls_ssl_set_hostname(&ssl, host.c_str());
        mbedtls_ssl_set_bio(&ssl, &server_fd, mbedtls_net_send, mbedtls_net_recv, NULL);

        while (running_) {
            int ret = mbedtls_ssl_handshake(&ssl);
            if (ret == 0) break;
            if (!isTransientTlsRet(ret)) goto cleanup;
        }
        if (!running_) goto cleanup;

        {
            std::string req =
                "GET " + path + " HTTP/1.1\r\n"
                "Host: " + host + "\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n";
            size_t written = 0;
            while (written < req.size() && running_) {
                int r = mbedtls_ssl_write(&ssl, (const unsigned char*)req.data() + written, req.size() - written);
                if (r > 0) written += r;
                else if (!isTransientTlsRet(r)) goto cleanup;
            }

            // Read HTTP 101 response header
            std::string hdr;
            unsigned char ch;
            while (running_ && hdr.find("\r\n\r\n") == std::string::npos && hdr.size() < 4096) {
                int r = mbedtls_ssl_read(&ssl, &ch, 1);
                if (r == 1) hdr.push_back((char)ch);
                else if (!isTransientTlsRet(r)) goto cleanup;
            }
            if (hdr.find("101") == std::string::npos) goto cleanup;
        }

        mbedtls_net_set_nonblock(&server_fd);
        connected_ = true;

        {
            std::vector<uint8_t> rxBuf;
            std::string fragBuf;
            uint8_t fragOpcode = 0;
            unsigned char tmp[8192];
            auto lastPing = std::chrono::steady_clock::now();

            while (running_) {
                // Flush outgoing frames
                std::vector<std::string> toSend;
                {
                    std::lock_guard<std::mutex> lk(mtx_);
                    toSend.swap(outbox_);
                }
                for (const auto& msg : toSend) {
                    std::vector<uint8_t> frame;
                    buildMaskedFrame(msg, frame);
                    size_t sent = 0;
                    while (sent < frame.size() && running_) {
                        int r = mbedtls_ssl_write(&ssl, frame.data() + sent, frame.size() - sent);
                        if (r > 0) sent += r;
                        else if (isTransientTlsRet(r)) {
                            usleep(2000);
                        } else {
                            running_ = false;
                            break;
                        }
                    }
                }

                // Periodic keepalive ping every 15s
                auto now = std::chrono::steady_clock::now();
                if (std::chrono::duration_cast<std::chrono::seconds>(now - lastPing).count() >= 15) {
                    uint8_t pingFrame[6] = {0x89, 0x80, 0x11, 0x22, 0x33, 0x44};
                    mbedtls_ssl_write(&ssl, pingFrame, sizeof(pingFrame));
                    lastPing = now;
                }

                // Drain incoming bytes (up to 8 reads per iteration)
                bool fatalReadErr = false;
                for (int reads = 0; reads < 8 && running_; ++reads) {
                    int r = mbedtls_ssl_read(&ssl, tmp, sizeof(tmp));
                    if (r > 0) {
                        rxBuf.insert(rxBuf.end(), tmp, tmp + r);
                    } else if (isTransientTlsRet(r)) {
                        break;
                    } else {
                        fatalReadErr = true;
                        break;
                    }
                }
                if (fatalReadErr) break;

                // Parse complete WebSocket frames (Text 0x01, Binary 0x02, and fragmented Continuation 0x00)
                while (rxBuf.size() >= 2) {
                    uint8_t b0 = rxBuf[0];
                    uint8_t b1 = rxBuf[1];
                    bool fin = (b0 & 0x80) != 0;
                    uint8_t opcode = b0 & 0x0F;
                    bool masked = (b1 & 0x80) != 0;
                    uint64_t payloadLen = b1 & 0x7F;
                    size_t headerSize = 2;
                    if (payloadLen == 126) {
                        if (rxBuf.size() < 4) break;
                        payloadLen = ((uint64_t)rxBuf[2] << 8) | rxBuf[3];
                        headerSize = 4;
                    } else if (payloadLen == 127) {
                        if (rxBuf.size() < 10) break;
                        payloadLen = 0;
                        for (int i = 0; i < 8; ++i) payloadLen = (payloadLen << 8) | rxBuf[2 + i];
                        headerSize = 10;
                    }
                    if (masked) headerSize += 4;
                    if (rxBuf.size() < headerSize + payloadLen) break;

                    std::string payload((const char*)(rxBuf.data() + headerSize), (size_t)payloadLen);
                    if (masked) {
                        const uint8_t* m = rxBuf.data() + headerSize - 4;
                        for (size_t i = 0; i < payload.size(); ++i) payload[i] ^= m[i & 3];
                    }
                    rxBuf.erase(rxBuf.begin(), rxBuf.begin() + headerSize + payloadLen);

                    if (opcode == 0x01 || opcode == 0x02) { // Text or Binary frame (iOS sends Binary 0x02!)
                        if (fin) {
                            std::lock_guard<std::mutex> lk(mtx_);
                            inbox_.push_back(std::move(payload));
                        } else {
                            fragOpcode = opcode;
                            fragBuf = std::move(payload);
                        }
                    } else if (opcode == 0x00) { // Continuation frame
                        if (fragOpcode == 0x01 || fragOpcode == 0x02) {
                            fragBuf += payload;
                            if (fin) {
                                std::lock_guard<std::mutex> lk(mtx_);
                                inbox_.push_back(std::move(fragBuf));
                                fragBuf.clear();
                                fragOpcode = 0;
                            }
                        }
                    } else if (opcode == 0x08) { // Close
                        running_ = false;
                        break;
                    } else if (opcode == 0x09) { // Ping -> Pong
                        uint8_t pong[6] = {0x8A, 0x80, 0, 0, 0, 0};
                        mbedtls_ssl_write(&ssl, pong, sizeof(pong));
                    }
                }

                usleep(12000);
            }
        }

    cleanup:
        connected_ = false;
        mbedtls_ssl_close_notify(&ssl);
        mbedtls_net_free(&server_fd);
        mbedtls_ssl_free(&ssl);
        mbedtls_ssl_config_free(&conf);
        mbedtls_ctr_drbg_free(&ctr_drbg);
        mbedtls_entropy_free(&entropy);
    }
};


// Lightweight synchronous HTTPS GET/POST helper (mbedTLS, for QQ Coin Binding)
inline std::string switchHttpsRequest(const std::string& method, const std::string& host, const std::string& port, const std::string& path, const std::string& body = "") {
    mbedtls_net_context server_fd;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_net_init(&server_fd);
    mbedtls_ssl_init(&ssl);
    mbedtls_ssl_config_init(&conf);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    mbedtls_entropy_init(&entropy);
    std::string resp;
    const char* pers = "htt_switch_https";
    if (mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy, (const unsigned char*)pers, strlen(pers)) != 0) goto done;
    if (mbedtls_net_connect(&server_fd, host.c_str(), port.c_str(), MBEDTLS_NET_PROTO_TCP) != 0) goto done;
    { struct timeval tv; tv.tv_sec = 6; tv.tv_usec = 0; setsockopt(server_fd.fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)); setsockopt(server_fd.fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv)); }
    if (mbedtls_ssl_config_defaults(&conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT) != 0) goto done;
    mbedtls_ssl_conf_authmode(&conf, MBEDTLS_SSL_VERIFY_NONE);
    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);
    if (mbedtls_ssl_setup(&ssl, &conf) != 0) goto done;
    mbedtls_ssl_set_hostname(&ssl, host.c_str());
    mbedtls_ssl_set_bio(&ssl, &server_fd, mbedtls_net_send, mbedtls_net_recv, NULL);
    while (true) {
        int r = mbedtls_ssl_handshake(&ssl);
        if (r == 0) break;
        if (r != MBEDTLS_ERR_SSL_WANT_READ && r != MBEDTLS_ERR_SSL_WANT_WRITE && r != -0x7880) goto done;
    }
    {
        std::string req = method + " " + path + " HTTP/1.1\r\nHost: " + host + "\r\nConnection: close\r\n";
        if (!body.empty()) {
            req += "Content-Type: application/json\r\nContent-Length: " + std::to_string(body.size()) + "\r\n";
        }
        req += "\r\n" + body;
        size_t sent = 0;
        while (sent < req.size()) {
            int r = mbedtls_ssl_write(&ssl, (const unsigned char*)req.data() + sent, req.size() - sent);
            if (r > 0) sent += r;
            else if (r != MBEDTLS_ERR_SSL_WANT_READ && r != MBEDTLS_ERR_SSL_WANT_WRITE) goto done;
        }
        unsigned char buf[2048];
        while (true) {
            int r = mbedtls_ssl_read(&ssl, buf, sizeof(buf));
            if (r > 0) resp.append((const char*)buf, r);
            else if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE || r == -0x7880) continue;
            else break;
        }
    }
done:
    mbedtls_ssl_close_notify(&ssl);
    mbedtls_net_free(&server_fd);
    mbedtls_ssl_free(&ssl);
    mbedtls_ssl_config_free(&conf);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    size_t hdrEnd = resp.find("\r\n\r\n");
    return (hdrEnd != std::string::npos) ? resp.substr(hdrEnd + 4) : "";
}
