// Command camesura-bridge relays Yaw Reset requests from the mobile app.
package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/camesura/camesura/bridge/internal/protocol"
	"github.com/camesura/camesura/bridge/internal/resetadapter"
	"github.com/camesura/camesura/bridge/internal/server"
)

func main() {
	listen := flag.String("listen", fmt.Sprintf(":%d", protocol.DefaultPort), "UDP address to listen on")
	adapterName := flag.String("adapter", "mock", "reset adapter (mock, slimevr)")
	slimevrURL := flag.String("slimevr-url", resetadapter.DefaultSlimeVRURL, "SlimeVR Server WebSocket URL (adapter=slimevr)")
	cooldown := flag.Duration("cooldown", server.DefaultCooldown, "per-device reset cooldown")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	if err := run(logger, *listen, *adapterName, *slimevrURL, *cooldown); err != nil {
		logger.Error("bridge stopped", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger, listen, adapterName, slimevrURL string, cooldown time.Duration) error {
	var adapter resetadapter.ResetAdapter
	switch adapterName {
	case "mock":
		adapter = &resetadapter.Mock{Logger: logger}
	case "slimevr":
		slimevr := resetadapter.NewSlimeVR(slimevrURL, logger)
		defer slimevr.Close()
		adapter = slimevr
	default:
		return fmt.Errorf("unknown adapter %q", adapterName)
	}

	conn, err := net.ListenPacket("udp4", listen)
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	port := conn.LocalAddr().(*net.UDPAddr).Port
	logger.Info("CameSura Bridge started", "listen", conn.LocalAddr(), "adapter", adapter.Name())
	for _, ip := range lanIPv4s() {
		logger.Info("enter this address in the mobile app", "ip", ip, "port", port)
	}

	srv := server.New(conn, server.Config{Adapter: adapter, Logger: logger, Cooldown: cooldown})
	return srv.Serve(ctx)
}

// virtualInterfacePrefixes are macOS/Linux interface names that are never the
// Wi-Fi link to a phone: Internet Sharing/Thunderbolt bridges, VPN tunnels,
// AWDL/Bonjour, container networking, etc. Listing their addresses only
// confuses users pairing a phone, since these are frequently unreachable
// network addresses (host part all zero) rather than real device addresses.
var virtualInterfacePrefixes = []string{
	"bridge", "utun", "awdl", "llw", "ap", "vnic", "docker", "anpi", "tap", "ipsec", "gif", "stf",
}

func lanIPv4s() []string {
	var ips []string
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		if isVirtualInterface(iface.Name) {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			ipNet, ok := addr.(*net.IPNet)
			if !ok {
				continue
			}
			ip4 := ipNet.IP.To4()
			if ip4 == nil || ip4.IsLinkLocalUnicast() {
				continue
			}
			// A host part of all zeros is the network address, never a real
			// device: it happens on macOS's placeholder bridge interfaces.
			if ip4.Equal(ip4.Mask(ipNet.Mask)) {
				continue
			}
			ips = append(ips, ip4.String())
		}
	}
	return ips
}

func isVirtualInterface(name string) bool {
	for _, prefix := range virtualInterfacePrefixes {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	return false
}
