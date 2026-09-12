#!/usr/bin/env python3

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

NATIVE = ROOT / "theme" / "native"
COMP = NATIVE / "components"


branding = (
    COMP / "BrandingConfig.qml"
).read_text(encoding="utf-8")

main = (
    NATIVE / "Main.qml"
).read_text(encoding="utf-8")

chooser = (
    COMP / "UserChooser.qml"
).read_text(encoding="utf-8")

panel = (
    COMP / "SmartphoneLoginPanel.qml"
).read_text(encoding="utf-8")

button = (
    COMP / "PolishedButton.qml"
).read_text(encoding="utf-8")

field = (
    COMP / "PolishedTextField.qml"
).read_text(encoding="utf-8")

combo = (
    COMP / "PolishedComboBox.qml"
).read_text(encoding="utf-8")

countdown = (
    COMP / "CountdownView.qml"
).read_text(encoding="utf-8")

theme_conf = (
    NATIVE / "theme.conf"
).read_text(encoding="utf-8")

example = (
    NATIVE / "theme.conf.user.example"
).read_text(encoding="utf-8")

metadata = (
    NATIVE / "metadata.desktop"
).read_text(encoding="utf-8")


checks = {
    "v1.16 main marker":
        "Native v1.16.0" in main,

    "v1.16 metadata":
        "Version=1.16.0" in metadata,

    "typed brand name":
        '"ui_brand_name"' in branding,

    "typed local logo":
        '"ui_brand_logo"' in branding,

    "typed hostname":
        '"ui_show_hostname"' in branding,

    "typed domain":
        '"ui_show_domain"' in branding
        and '"ui_brand_domain"' in branding,

    "typed avatar":
        '"ui_show_avatar"' in branding,

    "typed accent":
        '"ui_accent"' in branding
        and '"ui_accent_color"' in branding,

    "absolute logo only":
        'brandLogoPath.charAt(0) === "/"'
        in branding,

    "remote logo rejected":
        'brandLogoPath.indexOf("://") === -1'
        in branding,

    "opaque hex only":
        "/^#[0-9a-fA-F]{6}$/" in branding,

    "v1.12 default accent preserved":
        'defaultAccentColor: "#3478e8"'
        in branding,

    "main consumes branding":
        "BrandingConfig {" in main
        and "branding.brandName" in main
        and "branding.brandLogoSource" in main
        and "branding.contextLabel" in main,

    "hostname comes from SDDM":
        "sddm.hostName" in main,

    "avatar propagated":
        "showAvatar:" in chooser
        and "showAvatar:" in panel,

    "button custom accent":
        "useCustomAccent" in button,

    "field custom accent":
        "useCustomAccent" in field,

    "combo custom accent":
        "useCustomAccent" in combo,

    "countdown custom accent":
        "useCustomAccent" in countdown,

    "phone device accent":
        "root.accentColor.b" in panel
        and "0.24" in panel,

    "native default brand blank":
        "ui_brand_name=" in theme_conf,

    "native default logo blank":
        "ui_brand_logo=" in theme_conf,

    "native default hostname hidden":
        "ui_show_hostname=false"
        in theme_conf,

    "native default domain hidden":
        "ui_show_domain=false"
        in theme_conf,

    "native default avatar visible":
        "ui_show_avatar=true"
        in theme_conf,

    "native default system accent":
        "ui_accent=system"
        in theme_conf,

    "example complete":
        all(
            key in example
            for key in (
                "ui_brand_name=",
                "ui_brand_logo=",
                "ui_show_hostname=false",
                "ui_show_domain=false",
                "ui_brand_domain=",
                "ui_show_avatar=true",
                "ui_accent=system",
                "ui_accent_color=",
            )
        ),
}


failed = [
    name
    for name, passed
    in checks.items()
    if not passed
]

if failed:
    raise RuntimeError(
        "native branding contract failed: "
        + ", ".join(failed)
    )


for text, label in (
    (
        branding,
        "BrandingConfig.qml",
    ),
    (
        main,
        "Main.qml",
    ),
):
    if (
        "http://" in text
        or "https://" in text
    ):
        raise RuntimeError(
            f"{label}: remote resource "
            "literal found"
        )


print("NATIVE_BRANDING_STATIC=GREEN")
print("METADATA_VERSION=1.16.0")
print("REMOTE_BRAND_LOGOS=REJECTED")
print("DEFAULT_V112_APPEARANCE=PRESERVED")
print("AUTH_CONFIGURATION_SEPARATION=GREEN")
