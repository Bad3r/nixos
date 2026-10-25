/* Sends three crafted Ethernet frames for the workloads-vms test, which
 * busybox cannot do:
 *   sendframe IFACE SRC DST 88cc                  an empty frame
 *   sendframe IFACE SRC DST 0806 SHA SPA TPA      an ARP request
 *   sendframe IFACE SRC DST 0800 SRCIP DSTIP      UDP to port 4444
 */
#include <arpa/inet.h>
#include <linux/if_packet.h>
#include <net/if.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

static int mac(const char *text, unsigned char *out) {
  return sscanf(text, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx", &out[0], &out[1], &out[2], &out[3],
                &out[4], &out[5]) == 6;
}

static int ipv4(const char *text, unsigned char *out) { return inet_pton(AF_INET, text, out) == 1; }

static uint16_t checksum(const unsigned char *data, size_t length) {
  uint32_t sum = 0;
  for (size_t i = 0; i + 1 < length; i += 2) sum += (uint32_t)(data[i] << 8 | data[i + 1]);
  while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
  return (uint16_t)~sum;
}

int main(int argc, char **argv) {
  unsigned char frame[64] = {0};
  unsigned char *body = frame + 14;
  if (argc < 5 || !mac(argv[3], frame) || !mac(argv[2], frame + 6)) return 2;
  unsigned long type = strtoul(argv[4], NULL, 16);
  frame[12] = type >> 8;
  frame[13] = type & 0xff;
  if (type == 0x0806) {
    static const unsigned char header[] = {0, 1, 8, 0, 6, 4, 0, 1};
    if (argc != 8) return 2;
    memcpy(body, header, sizeof header);
    if (!mac(argv[5], body + 8) || !ipv4(argv[6], body + 14) || !ipv4(argv[7], body + 24)) return 2;
  } else if (type == 0x0800) {
    if (argc != 7) return 2;
    body[0] = 0x45;
    body[3] = 30;
    body[8] = 64;
    body[9] = 17;
    if (!ipv4(argv[5], body + 12) || !ipv4(argv[6], body + 16)) return 2;
    uint16_t sum = checksum(body, 20);
    body[10] = sum >> 8;
    body[11] = sum & 0xff;
    unsigned char *udp = body + 20;
    udp[0] = 0x0f;
    udp[1] = 0xa0;
    udp[2] = 4444 >> 8;
    udp[3] = 4444 & 0xff;
    udp[5] = 10;
  } else if (argc != 5) {
    return 2;
  }
  struct sockaddr_ll to = {0};
  int sock = socket(AF_PACKET, SOCK_RAW, 0);
  if (sock < 0) return 1;
  to.sll_family = AF_PACKET;
  to.sll_ifindex = (int)if_nametoindex(argv[1]);
  to.sll_halen = 6;
  memcpy(to.sll_addr, frame, 6);
  for (int i = 0; i < 3; i++)
    if (sendto(sock, frame, sizeof frame, 0, (struct sockaddr *)&to, sizeof to) < 0) return 1;
  return 0;
}
