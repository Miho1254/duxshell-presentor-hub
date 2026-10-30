import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "presentationHub"

    StyledText {
        width: parent.width
        text: "Browser detection"
        color: Theme.surfaceText
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
    }

    StringSetting {
        settingKey: "additionalBrowserAppIds"
        label: "Additional browser app IDs"
        description: "Comma-separated exact app IDs for browsers that are not detected automatically. Find an app ID with niri msg windows."
        placeholder: "org.example.Browser, another-browser"
        defaultValue: ""
    }
}
