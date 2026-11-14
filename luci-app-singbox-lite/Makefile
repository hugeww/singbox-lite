include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-singbox-lite
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=singbox-lite contributors

LUCI_TITLE:=LuCI support for singbox-lite
LUCI_DEPENDS:=+luci-base +singbox-lite +rpcd-mod-ucode +rpcd-mod-file
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
