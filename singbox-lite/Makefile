include $(TOPDIR)/rules.mk

PKG_NAME:=singbox-lite
PKG_VERSION:=0.1.0
PKG_RELEASE:=1
PKGARCH:=all

PKG_LICENSE:=GPL-3.0-or-later
PKG_MAINTAINER:=singbox-lite contributors

include $(INCLUDE_DIR)/package.mk

define Package/singbox-lite
  SECTION:=net
  CATEGORY:=Network
  TITLE:=sing-box TUN/auto_redirect manager (backend)
  URL:=https://github.com/hugeww/singbox-lite
  DEPENDS:=+curl +ca-bundle +unzip +ucode +ucode-mod-fs +ucode-mod-uci \
	+kmod-tun +kmod-nft-core +kmod-nft-nat +kmod-nft-queue +kmod-nfnetlink-queue
  PKGARCH:=all
endef

define Package/singbox-lite/description
  Backend for the sing-box TUN manager: subscription conversion, rule-set and
  egress-group configuration, TUN + auto_redirect config generation, scheduled
  refresh and core updates.
endef

define Package/singbox-lite/conffiles
/etc/config/singbox-lite
endef

define Package/singbox-lite/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/singbox-lite $(1)/etc/config/singbox-lite

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/singbox-lite $(1)/etc/init.d/singbox-lite

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/99_singbox_lite $(1)/etc/uci-defaults/99_singbox_lite

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/singbox-lite $(1)/usr/bin/singbox-lite

	$(INSTALL_DIR) $(1)/usr/share/singbox-lite
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/cli.uc $(1)/usr/share/singbox-lite/cli.uc

	$(INSTALL_DIR) $(1)/usr/share/ucode
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/common.uc $(1)/usr/share/ucode/sbx_common.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/config.uc $(1)/usr/share/ucode/sbx_config.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/links.uc $(1)/usr/share/ucode/sbx_links.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/nodes.uc $(1)/usr/share/ucode/sbx_nodes.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/rulesets.uc $(1)/usr/share/ucode/sbx_rulesets.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/subs.uc $(1)/usr/share/ucode/sbx_subs.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/generator.uc $(1)/usr/share/ucode/sbx_generator.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/core.uc $(1)/usr/share/ucode/sbx_core.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/releases.uc $(1)/usr/share/ucode/sbx_releases.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/plugin.uc $(1)/usr/share/ucode/sbx_plugin.uc
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/ucode/panel.uc $(1)/usr/share/ucode/sbx_panel.uc

	$(INSTALL_DIR) $(1)/usr/share/singbox-lite/rulesets
	$(INSTALL_DATA) ./files/usr/share/singbox-lite/rulesets/* $(1)/usr/share/singbox-lite/rulesets/

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/lib/upgrade/keep.d/singbox-lite $(1)/lib/upgrade/keep.d/singbox-lite
endef

define Package/singbox-lite/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
mkdir -p /etc/singbox-lite/subs /etc/singbox-lite/meta /etc/singbox-lite/rulesets
mkdir -p /var/log/singbox-lite
chmod 700 /etc/singbox-lite
exit 0
endef

define Package/singbox-lite/postrm
#!/bin/sh
# Destructive cleanup must run on removal, but not when opkg calls postrm for
# an upgrade. APK maps this script to post-deinstall and may call it without
# arguments, so only skip the explicit opkg "upgrade" case.
if [ "$$1" = "upgrade" ]; then
	exit 0
fi
if [ -n "$${IPKG_INSTROOT}" ]; then
	exit 0
fi
/etc/init.d/singbox-lite stop >/dev/null 2>&1 || true
/etc/init.d/singbox-lite disable >/dev/null 2>&1 || true
sed -i '/# singbox-lite/d' /etc/crontabs/root >/dev/null 2>&1 || true
rm -rf /usr/libexec/singbox-lite
exit 0
endef

define Build/Compile
endef

$(eval $(call BuildPackage,singbox-lite))
