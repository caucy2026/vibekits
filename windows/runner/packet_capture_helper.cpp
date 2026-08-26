#include <winsock2.h>
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>

#include "windivert.h"

#pragma pack(push, 1)
struct PcapHeader {
  uint32_t magic = 0xa1b2c3d4;
  uint16_t major = 2;
  uint16_t minor = 4;
  int32_t timezone = 0;
  uint32_t accuracy = 0;
  uint32_t snaplen = 0xffff;
  uint32_t network = 101;  // LINKTYPE_RAW: IPv4/IPv6 without Ethernet header.
};

struct PcapPacketHeader {
  uint32_t seconds;
  uint32_t micros;
  uint32_t captured_length;
  uint32_t original_length;
};
#pragma pack(pop)

static std::atomic<bool> running{true};
static HANDLE divert_handle = INVALID_HANDLE_VALUE;

static std::string json_escape(const std::string& value) {
  std::string result;
  result.reserve(value.size() + 8);
  for (const char ch : value) {
    if (ch == '\\' || ch == '"') result.push_back('\\');
    if (ch == '\n') {
      result += "\\n";
    } else if (ch == '\r') {
      result += "\\r";
    } else {
      result.push_back(ch);
    }
  }
  return result;
}

static uint64_t unix_micros() {
  FILETIME time;
  GetSystemTimeAsFileTime(&time);
  ULARGE_INTEGER raw;
  raw.LowPart = time.dwLowDateTime;
  raw.HighPart = time.dwHighDateTime;
  return (raw.QuadPart - 116444736000000000ULL) / 10ULL;
}

static void write_test_packet(FILE* output) {
  // Minimal IPv4/UDP packet, sufficient for deterministic packaging tests.
  const unsigned char packet[] = {
      0x45, 0x00, 0x00, 0x20, 0x00, 0x01, 0x00, 0x00, 0x40, 0x11, 0x00, 0x00,
      0x7f, 0x00, 0x00, 0x01, 0x08, 0x08, 0x08, 0x08, 0xc3, 0x50, 0x00, 0x35,
      0x00, 0x0c, 0x00, 0x00, 0x56, 0x49, 0x42, 0x45};
  const uint64_t now = unix_micros();
  const PcapPacketHeader header{static_cast<uint32_t>(now / 1000000ULL),
                                static_cast<uint32_t>(now % 1000000ULL),
                                sizeof(packet), sizeof(packet)};
  fwrite(&header, sizeof(header), 1, output);
  fwrite(packet, sizeof(packet), 1, output);
  fflush(output);
  std::cout << "{\"type\":\"packet\",\"timestampMicros\":" << now
            << ",\"direction\":\"outbound\",\"interfaceIndex\":0,"
               "\"protocol\":\"UDP\",\"source\":\"127.0.0.1:50000\","
               "\"destination\":\"8.8.8.8:53\",\"length\":32}"
            << std::endl;
}

int main(int argc, char** argv) {
  std::string output_path;
  std::string filter = "true";
  uint64_t max_packets = 0;
  bool self_test = false;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    if (arg == "--output" && i + 1 < argc) output_path = argv[++i];
    else if (arg == "--filter" && i + 1 < argc) filter = argv[++i];
    else if (arg == "--max-packets" && i + 1 < argc)
      max_packets = std::strtoull(argv[++i], nullptr, 10);
    else if (arg == "--self-test") self_test = true;
  }
  if (output_path.empty()) {
    std::cerr << "{\"type\":\"error\",\"message\":\"missing --output\"}"
              << std::endl;
    return 2;
  }

  FILE* output = nullptr;
  if (fopen_s(&output, output_path.c_str(), "wb") != 0 || output == nullptr) {
    std::cerr << "{\"type\":\"error\",\"message\":\"cannot open output\"}"
              << std::endl;
    return 3;
  }
  const PcapHeader pcap_header;
  fwrite(&pcap_header, sizeof(pcap_header), 1, output);
  if (self_test) {
    write_test_packet(output);
    fclose(output);
    std::cout << "{\"type\":\"stopped\",\"packets\":1}" << std::endl;
    return 0;
  }

  divert_handle = WinDivertOpen(filter.c_str(), WINDIVERT_LAYER_NETWORK, 0,
                                WINDIVERT_FLAG_SNIFF | WINDIVERT_FLAG_RECV_ONLY);
  if (divert_handle == INVALID_HANDLE_VALUE) {
    const DWORD error = GetLastError();
    fclose(output);
    std::cerr << "{\"type\":\"error\",\"code\":" << error
              << ",\"message\":\"WinDivertOpen failed; run VibeKits as administrator\"}"
              << std::endl;
    return 4;
  }
  std::thread input_thread([] {
    std::string line;
    std::getline(std::cin, line);
    running = false;
    if (divert_handle != INVALID_HANDLE_VALUE) WinDivertShutdown(divert_handle, WINDIVERT_SHUTDOWN_RECV);
  });
  input_thread.detach();
  std::cout << "{\"type\":\"started\",\"filter\":\""
            << json_escape(filter) << "\"}" << std::endl;

  unsigned char packet[0xffff];
  WINDIVERT_ADDRESS address{};
  UINT packet_length = 0;
  uint64_t count = 0;
  while (running && (max_packets == 0 || count < max_packets)) {
    if (!WinDivertRecv(divert_handle, packet, sizeof(packet), &packet_length,
                       &address)) {
      if (!running || GetLastError() == ERROR_NO_DATA) break;
      continue;
    }
    const uint64_t now = unix_micros();
    const PcapPacketHeader packet_header{
        static_cast<uint32_t>(now / 1000000ULL),
        static_cast<uint32_t>(now % 1000000ULL), packet_length, packet_length};
    fwrite(&packet_header, sizeof(packet_header), 1, output);
    fwrite(packet, packet_length, 1, output);
    fflush(output);

    WINDIVERT_IPHDR* ip = nullptr;
    WINDIVERT_IPV6HDR* ipv6 = nullptr;
    WINDIVERT_TCPHDR* tcp = nullptr;
    WINDIVERT_UDPHDR* udp = nullptr;
    UINT8 protocol = 0;
    WinDivertHelperParsePacket(packet, packet_length, &ip, &ipv6, &protocol,
                               nullptr, nullptr, &tcp, &udp, nullptr, nullptr,
                               nullptr, nullptr);
    char source[64] = "?";
    char destination[64] = "?";
    if (ip != nullptr) {
      WinDivertHelperFormatIPv4Address(ip->SrcAddr, source, sizeof(source));
      WinDivertHelperFormatIPv4Address(ip->DstAddr, destination,
                                      sizeof(destination));
    } else if (ipv6 != nullptr) {
      WinDivertHelperFormatIPv6Address(ipv6->SrcAddr, source, sizeof(source));
      WinDivertHelperFormatIPv6Address(ipv6->DstAddr, destination,
                                      sizeof(destination));
    }
    uint16_t source_port = 0;
    uint16_t destination_port = 0;
    const char* protocol_name = protocol == IPPROTO_TCP ? "TCP" :
                                protocol == IPPROTO_UDP ? "UDP" :
                                protocol == IPPROTO_ICMP ? "ICMP" :
                                protocol == 58 ? "ICMPv6" : "IP";
    if (tcp != nullptr) {
      source_port = ntohs(tcp->SrcPort);
      destination_port = ntohs(tcp->DstPort);
    } else if (udp != nullptr) {
      source_port = ntohs(udp->SrcPort);
      destination_port = ntohs(udp->DstPort);
    }
    std::cout << "{\"type\":\"packet\",\"timestampMicros\":" << now
              << ",\"direction\":\"" << (address.Outbound ? "outbound" : "inbound")
              << "\",\"interfaceIndex\":" << address.Network.IfIdx
              << ",\"protocol\":\"" << protocol_name << "\",\"source\":\""
              << source << (source_port ? ":" + std::to_string(source_port) : "")
              << "\",\"destination\":\"" << destination
              << (destination_port ? ":" + std::to_string(destination_port) : "")
              << "\",\"length\":" << packet_length << "}" << std::endl;
    ++count;
  }
  WinDivertClose(divert_handle);
  divert_handle = INVALID_HANDLE_VALUE;
  fclose(output);
  std::cout << "{\"type\":\"stopped\",\"packets\":" << count << "}"
            << std::endl;
  return 0;
}
